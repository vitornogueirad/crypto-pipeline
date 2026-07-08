"""
Consumer Lambda — processa trades da Binance vindos do Kinesis.

Fluxo: decodifica → dedup em memória → dedup paralelo no DynamoDB
- grava 1 arquivo no S3 → (se S3 falhar: ROLLBACK das marcas de dedup)
- reporta falhas parciais.

Edge case tratado:
  O dedup marca o trade_id no DynamoDB antes da escrita no S3. Se o S3
  falhar, os IDs ficariam marcados como "processados" sem dado persistido e
  no retry, o dedup diria "duplicado" e os trades seriam perdidos.
  Solução: em falha de S3, as marcas são removidas (delete_item) antes de
  reportar o batch como falho. Não há transação entre DynamoDB e S3;
  a compensação fecha essa janela.
"""
import base64
import json
import logging
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

BUCKET = os.environ["RAW_BUCKET"]
DEDUP_TABLE = os.environ["DEDUP_TABLE"]
DEDUP_TTL_HOURS = int(os.environ.get("DEDUP_TTL_HOURS", "6"))
DEDUP_MAX_WORKERS = int(os.environ.get("DEDUP_MAX_WORKERS", "25"))

_clients: dict = {}


def _client(service: str):
    if service not in _clients:
        _clients[service] = boto3.client(service)
    return _clients[service]


def _resource(service: str):
    key = f"resource:{service}"
    if key not in _clients:
        _clients[key] = boto3.resource(service)
    return _clients[key]


def _ja_processado(trade_id: str) -> bool:
    """
    Check-and-set atômico: put_item condicional. Retorna True se o ID
    já existia (duplicado), False se é novo (e marca).
    """
    table = _resource("dynamodb").Table(DEDUP_TABLE)
    ttl_epoch = int(datetime.now(timezone.utc).timestamp()) + DEDUP_TTL_HOURS * 3600
    try:
        table.put_item(
            Item={"trade_id": trade_id, "ttl": ttl_epoch},
            ConditionExpression="attribute_not_exists(trade_id)",
        )
        return False
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return True
        raise


def _filtrar_novos(candidatos: list[tuple[str, dict]]) -> tuple[list[dict], set[str]]:
    """Checa o DynamoDB em paralelo. Retorna (trades_novos, ids_com_erro)."""
    novos: list[dict] = []
    ids_com_erro: set[str] = set()

    def checar(item: tuple[str, dict]):
        trade_id, trade = item
        try:
            return (trade, None) if not _ja_processado(trade_id) else (None, None)
        except Exception as exc:  # noqa: BLE001
            logger.error("Erro no dedup do trade %s: %s", trade_id, exc)
            return (None, trade_id)

    with ThreadPoolExecutor(max_workers=DEDUP_MAX_WORKERS) as pool:
        for trade, erro_id in pool.map(checar, candidatos):
            if trade is not None:
                novos.append(trade)
            if erro_id is not None:
                ids_com_erro.add(erro_id)

    return novos, ids_com_erro


def _desfazer_marcas(trade_ids: list[str]) -> None:
    """
    COMPENSAÇÃO: remove as marcas de dedup dos trades que não foram
    persistidos no S3, para o retry do batch não os tratar como duplicados.
    Best-effort: falha no delete é logada, não propagada (o TTL de 6h
    é o backstop final para marcas órfãs).
    """
    table = _resource("dynamodb").Table(DEDUP_TABLE)

    def deletar(trade_id: str):
        try:
            table.delete_item(Key={"trade_id": trade_id})
        except Exception as exc:  # noqa: BLE001
            logger.error("Rollback falhou para trade %s: %s (TTL limpará)", trade_id, exc)

    with ThreadPoolExecutor(max_workers=DEDUP_MAX_WORKERS) as pool:
        list(pool.map(deletar, trade_ids))
    logger.warning("Rollback: %d marcas de dedup removidas.", len(trade_ids))


def _build_s3_key(now: datetime, request_id: str) -> str:
    """Um arquivo por batch, particionado Hive-style."""
    return (
        f"bronze/trades/"
        f"year={now:%Y}/month={now:%m}/day={now:%d}/hour={now:%H}/"
        f"trades_{now:%Y%m%dT%H%M%S}_{request_id}.jsonl"
    )


def handler(event, context):
    falhas = []
    now = datetime.now(timezone.utc)
    ingested_at = now.isoformat()

    vistos_no_batch: set[str] = set()
    candidatos: list[tuple[str, dict]] = []
    seq_por_trade: dict[str, str] = {}

    for record in event["Records"]:
        seq = record["kinesis"]["sequenceNumber"]
        try:
            payload = base64.b64decode(record["kinesis"]["data"])
            trade = json.loads(payload)
            trade_id = str(trade["trade_id"])

            if trade_id in vistos_no_batch:
                continue
            vistos_no_batch.add(trade_id)

            trade["_ingested_at"] = ingested_at
            candidatos.append((trade_id, trade))
            seq_por_trade[trade_id] = seq
        except Exception as exc:  # noqa: BLE001
            logger.error("Falha ao decodificar registro %s: %s", seq, exc)
            falhas.append({"itemIdentifier": seq})

    # dedup no DynamoDB em PARALELO (marca os novos)
    trades_novos, ids_com_erro = _filtrar_novos(candidatos)

    for trade_id in ids_com_erro:
        falhas.append({"itemIdentifier": seq_por_trade[trade_id]})

    # grava um arquivo; se falhar, desfaz as marcas
    if trades_novos:
        request_id = getattr(context, "aws_request_id", "local")
        body = "\n".join(json.dumps(t, ensure_ascii=False) for t in trades_novos)
        key = _build_s3_key(now, request_id)
        try:
            _client("s3").put_object(
                Bucket=BUCKET,
                Key=key,
                Body=body.encode("utf-8"),
                ContentType="application/x-ndjson",
            )
            logger.info(
                "Gravados %d trades em s3://%s/%s (batch de %d registros)",
                len(trades_novos), BUCKET, key, len(event["Records"]),
            )
        except Exception as exc:  # noqa: BLE001
            logger.error("Falha ao gravar batch no S3: %s", exc)
            # libera os IDs para o retry não os ver como dups
            _desfazer_marcas([str(t["trade_id"]) for t in trades_novos])
            falhas = [
                {"itemIdentifier": r["kinesis"]["sequenceNumber"]}
                for r in event["Records"]
            ]

    if falhas:
        logger.warning("%d registros falharam.", len(falhas))

    return {"batchItemFailures": falhas}
