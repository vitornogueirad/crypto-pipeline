"""
Testes do cálculo de partições (year/month/day/hour) a processar.
"""
from datetime import datetime, timezone

from conftest import load_module

partitions = load_module("partitions", "src/transform/common/partitions.py")


def test_retorna_hora_atual_e_anterior():
    referencia = datetime(2026, 7, 16, 14, 30, tzinfo=timezone.utc)

    resultado = partitions.particoes_a_processar(referencia)

    assert resultado == [
        {"year": "2026", "month": "07", "day": "16", "hour": "14"},
        {"year": "2026", "month": "07", "day": "16", "hour": "13"},
    ]


def test_virada_de_dia():
    referencia = datetime(2026, 7, 16, 0, 15, tzinfo=timezone.utc)

    resultado = partitions.particoes_a_processar(referencia)

    assert resultado == [
        {"year": "2026", "month": "07", "day": "16", "hour": "00"},
        {"year": "2026", "month": "07", "day": "15", "hour": "23"},
    ]


def test_virada_de_ano():
    referencia = datetime(2027, 1, 1, 0, 5, tzinfo=timezone.utc)

    resultado = partitions.particoes_a_processar(referencia)

    assert resultado == [
        {"year": "2027", "month": "01", "day": "01", "hour": "00"},
        {"year": "2026", "month": "12", "day": "31", "hour": "23"},
    ]


def test_usa_hora_atual_quando_nao_informada():
    resultado = partitions.particoes_a_processar()

    assert len(resultado) == 2
    assert all(set(p.keys()) == {"year", "month", "day", "hour"} for p in resultado)
