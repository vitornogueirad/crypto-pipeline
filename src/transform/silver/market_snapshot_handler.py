"""
Lambda: transforma bronze.coingecko -> silver.market_snapshot via
MERGE INTO no Athena. Mesmo padrão do trades_handler.py.
"""
import os
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent))                     # zip do Lambda: tudo no mesmo diretório
sys.path.append(str(Path(__file__).parent.parent / "common"))   # repo local: common/ é vizinho de silver/

from transform_runner import processar_particoes  # noqa: E402

ATHENA_WORKGROUP = os.environ["ATHENA_WORKGROUP"]
SILVER_DATABASE = os.environ.get("SILVER_DATABASE", "silver")

QUERY_TEMPLATE = (Path(__file__).parent / "silver_market_snapshot_merge.sql").read_text(encoding="utf-8")


def handler(event, context):
    backfill = bool((event or {}).get("backfill", False))
    return processar_particoes(
        QUERY_TEMPLATE, database=SILVER_DATABASE, workgroup=ATHENA_WORKGROUP, backfill=backfill
    )
