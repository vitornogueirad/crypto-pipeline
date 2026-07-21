"""
Orquestra o processamento de múltiplas partições para uma query de
transformação (MERGE INTO) — usado pelos handlers de silver_trades e
silver_market_snapshot, que só diferem na query e no schema alvo.
"""
import logging
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent))  # garante import dos módulos vizinhos, mesmo fora de pacote

from athena_executor import AthenaQueryError, AthenaQueryTimeoutError, executar_query_sincrona  # noqa: E402
from partitions import particoes_a_processar  # noqa: E402

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def processar_particoes(query_template: str, database: str, workgroup: str, backfill: bool = False) -> dict:
    """
    Roda a query de MERGE no Athena.

    Modo incremental (padrão, backfill=False): roda uma vez para cada
    partição retornada por particoes_a_processar() (hora atual + hora
    anterior) — usado pelo disparo periódico via EventBridge.

    Modo backfill (backfill=True): roda uma única vez, sem filtro de
    partição ({particao_filtro} = "1=1"), processando a tabela bronze
    inteira. Usado para carregar dado histórico que já existia antes
    da Lambda começar a rodar (ex: batch acumulado da CoinGecko antes
    da silver existir). Seguro rodar mesmo com dado repetido, já que
    o MERGE é idempotente — não duplica o que já foi processado.

    Falha em uma partição (modo incremental) não interrompe as demais
    — todas são tentadas, e o erro agregado é levantado no final
    (mesmo padrão de "falha parcial, não falha total" do consumer de
    trades).
    """
    if backfill:
        query = query_template.format(particao_filtro="1=1")
        executar_query_sincrona(query, database=database, workgroup=workgroup)
        logger.info("Backfill concluído com sucesso.")
        return {"statusCode": 200, "modo": "backfill"}

    particoes = particoes_a_processar()
    falhas = []

    for particao in particoes:
        filtro = "year = '{year}' AND month = '{month}' AND day = '{day}' AND hour = '{hour}'".format(**particao)
        query = query_template.format(particao_filtro=filtro)
        try:
            executar_query_sincrona(query, database=database, workgroup=workgroup)
            logger.info("Partição processada com sucesso: %s", particao)
        except (AthenaQueryError, AthenaQueryTimeoutError) as exc:
            logger.error("Falha ao processar partição %s: %s", particao, exc)
            falhas.append({"particao": particao, "erro": str(exc)})

    if falhas:
        raise RuntimeError(f"{len(falhas)} partição(ões) falharam: {falhas}")

    return {"statusCode": 200, "modo": "incremental", "particoes_processadas": len(particoes)}