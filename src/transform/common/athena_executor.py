"""
Executor genérico de queries no Athena: dispara via start_query_execution
e faz polling síncrono até a query concluir (SUCCEEDED/FAILED/CANCELLED).

Usado por qualquer Lambda de transformação (silver e gold) —
a lógica de espera é a mesma, independente da query em si.
"""
import logging
import time

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

POLL_INTERVAL_SECONDS = 2
MAX_POLL_ATTEMPTS = 60  # 60 * 2s = 2 minutos de espera máxima por query


class AthenaQueryError(RuntimeError):
    """Query do Athena terminou em FAILED ou CANCELLED."""


class AthenaQueryTimeoutError(RuntimeError):
    """Query do Athena não concluiu dentro do tempo máximo de espera."""


def executar_query_sincrona(query: str, database: str, workgroup: str, client=None) -> str:
    """
    Envia uma query ao Athena e aguarda a conclusão de forma síncrona.

    Retorna o query_execution_id em caso de sucesso (SUCCEEDED).
    Lança AthenaQueryError se a query falhar ou for cancelada.
    Lança AthenaQueryTimeoutError se exceder MAX_POLL_ATTEMPTS.
    """
    athena = client or boto3.client("athena")

    response = athena.start_query_execution(
        QueryString=query,
        QueryExecutionContext={"Database": database},
        WorkGroup=workgroup,
    )
    execution_id = response["QueryExecutionId"]
    logger.info("Query Athena iniciada: execution_id=%s database=%s", execution_id, database)

    for _ in range(MAX_POLL_ATTEMPTS):
        resultado = athena.get_query_execution(QueryExecutionId=execution_id)
        status = resultado["QueryExecution"]["Status"]
        state = status["State"]

        if state == "SUCCEEDED":
            logger.info("Query Athena concluída: execution_id=%s", execution_id)
            return execution_id

        if state in ("FAILED", "CANCELLED"):
            motivo = status.get("StateChangeReason", "motivo não informado")
            raise AthenaQueryError(
                f"Query Athena {state}: {motivo} (execution_id={execution_id})"
            )

        # state em QUEUED ou RUNNING — continua aguardando
        time.sleep(POLL_INTERVAL_SECONDS)

    raise AthenaQueryTimeoutError(
        f"Query Athena não concluiu em {MAX_POLL_ATTEMPTS * POLL_INTERVAL_SECONDS}s "
        f"(execution_id={execution_id})"
    )
