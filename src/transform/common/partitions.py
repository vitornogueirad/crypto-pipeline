"""
Calcula as partições (year/month/day/hour) que devem ser processadas
em cada execução da Lambda de transformação.
"""
from datetime import datetime, timedelta, timezone
from typing import Optional


def particoes_a_processar(agora: Optional[datetime] = None) -> list:
    """
    Retorna a partição da hora atual e da hora anterior, em UTC.

    Processar as duas (não só a atual) cobre o caso de dado do bronze
    que termina de ser gravado bem na virada da hora — se a Lambda
    roda às HH:02, ainda pode existir escrita tardia na partição HH-1.
    Como o MERGE INTO é idempotente (WHEN NOT MATCHED THEN INSERT),
    reprocessar uma partição já processada não duplica nada.
    """
    referencia = agora or datetime.now(timezone.utc)
    horas = [referencia, referencia - timedelta(hours=1)]

    return [
        {
            "year": h.strftime("%Y"),
            "month": h.strftime("%m"),
            "day": h.strftime("%d"),
            "hour": h.strftime("%H"),
        }
        for h in horas
    ]
