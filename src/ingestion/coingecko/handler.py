"""
Lambda de ingestão batch da CoinGecko API.

Acionada pelo EventBridge a cada hora. Busca preços/market data das
moedas configuradas e grava o JSON bruto no S3 (camada bronze),
particionado por data/hora.

A chave de API fica no Secrets Manager.
"""
import json
import logging
import os
from datetime import datetime, timezone
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Variáveis de ambiente injetadas pelo Terraform
BUCKET = os.environ["RAW_BUCKET"]
SECRET_NAME = os.environ["COINGECKO_SECRET_NAME"]
COINS = os.environ.get("COINS", "bitcoin,ethereum,solana,cardano")
VS_CURRENCY = os.environ.get("VS_CURRENCY", "usd")

COINGECKO_URL = "https://api.coingecko.com/api/v3/coins/markets"

# Clients inicializados de forma lazy (só quando usados).
# Evita criar conexões no import e torna o módulo testável sem AWS.
_clients: dict = {}


def _client(service: str):
    if service not in _clients:
        _clients[service] = boto3.client(service)
    return _clients[service]


def _get_api_key() -> str:
    """Recupera a chave da CoinGecko do Secrets Manager."""
    response = _client("secretsmanager").get_secret_value(SecretId=SECRET_NAME)
    secret = json.loads(response["SecretString"])
    return secret["api_key"]


def _fetch_market_data(api_key: str) -> list[dict]:
    """Chama a CoinGecko e retorna a lista de market data."""
    params = (
        f"?vs_currency={VS_CURRENCY}"
        f"&ids={COINS}"
        f"&order=market_cap_desc"
        f"&sparkline=false"
        f"&price_change_percentage=1h,24h,7d"
    )
    request = Request(
        COINGECKO_URL + params,
        headers={"x-cg-demo-api-key": api_key, "Accept": "application/json"},
    )
    with urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def _build_s3_key(now: datetime) -> str:
    """
    Monta a chave do S3 com particionamento Hive-style.
    Ex: bronze/coingecko/year=2026/month=06/day=10/hour=14/markets_20260610T140000Z.json
    """
    return (
        f"bronze/coingecko/"
        f"year={now:%Y}/month={now:%m}/day={now:%d}/hour={now:%H}/"
        f"markets_{now:%Y%m%dT%H%M%SZ}.json"
    )


def handler(event, context):
    now = datetime.now(timezone.utc)

    try:
        api_key = _get_api_key()
        data = _fetch_market_data(api_key)
    except (HTTPError, URLError) as exc:
        logger.error("Falha ao chamar a CoinGecko: %s", exc)
        raise
    except Exception as exc:  # noqa: BLE001
        logger.error("Erro inesperado na ingestão: %s", exc)
        raise

    if not data:
        logger.warning("CoinGecko retornou lista vazia — nada a gravar.")
        return {"statusCode": 204, "records": 0}

    # Adiciona metadado de ingestão em cada registro
    ingested_at = now.isoformat()
    for record in data:
        record["ingested_at"] = ingested_at

    # Grava como JSON Lines (um registro por linha)
    body = "\n".join(json.dumps(r, ensure_ascii=False) for r in data)
    key = _build_s3_key(now)

    _client("s3").put_object(
        Bucket=BUCKET,
        Key=key,
        Body=body.encode("utf-8"),
        ContentType="application/x-ndjson",
    )

    logger.info("Gravados %d registros em s3://%s/%s", len(data), BUCKET, key)
    return {"statusCode": 200, "records": len(data), "s3_key": key}
