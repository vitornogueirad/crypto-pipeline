"""
Lambda: recalcula gold.anomalias via MERGE INTO no Athena.

Diferente das transformações da silver, esta NÃO é parametrizada por
partição — o baseline móvel (6h) é window function e precisa ver o
histórico inteiro de silver.market_snapshot em cada execução; não dá
pra restringir a "hora atual + hora anterior" sem quebrar o cálculo.

A query em si mora em gold_anomalias_merge.sql, vizinho deste arquivo.
"""
import logging
import os
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).parent))                     # zip do Lambda: tudo no mesmo diretório
sys.path.append(str(Path(__file__).parent.parent / "common"))   # repo local: common/ é vizinho de gold/

from athena_executor import executar_query_sincrona  # noqa: E402

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ATHENA_WORKGROUP = os.environ["ATHENA_WORKGROUP"]
GOLD_DATABASE = os.environ.get("GOLD_DATABASE", "gold")

QUERY = (Path(__file__).parent / "gold_anomalias_merge.sql").read_text(encoding="utf-8")


def handler(event, context):
    executar_query_sincrona(QUERY, database=GOLD_DATABASE, workgroup=ATHENA_WORKGROUP)
    logger.info("gold.anomalias atualizada com sucesso.")
    return {"statusCode": 200}
