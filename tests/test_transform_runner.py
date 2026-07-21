"""
Testes da orquestração de múltiplas partições (transform_runner).
Roda sem AWS real — mocka executar_query_sincrona e particoes_a_processar.
"""
from unittest.mock import patch

import pytest

from conftest import load_module

transform_runner = load_module("transform_runner", "src/transform/common/transform_runner.py")

PARTICOES_TESTE = [
    {"year": "2026", "month": "07", "day": "16", "hour": "14"},
    {"year": "2026", "month": "07", "day": "16", "hour": "13"},
]


def test_modo_incremental_todas_particoes_ok():
    with patch.object(transform_runner, "particoes_a_processar", return_value=PARTICOES_TESTE[:1]), \
         patch.object(transform_runner, "executar_query_sincrona") as mock_exec:
        resultado = transform_runner.processar_particoes("SELECT WHERE {particao_filtro}", database="silver", workgroup="wg")

    mock_exec.assert_called_once()
    assert resultado == {"statusCode": 200, "modo": "incremental", "particoes_processadas": 1}


def test_modo_incremental_query_formatada_com_filtro_de_particao():
    with patch.object(transform_runner, "particoes_a_processar", return_value=PARTICOES_TESTE[:1]), \
         patch.object(transform_runner, "executar_query_sincrona") as mock_exec:
        transform_runner.processar_particoes("WHERE {particao_filtro}", database="silver", workgroup="wg")

    query_enviada = mock_exec.call_args[0][0]
    assert query_enviada == "WHERE year = '2026' AND month = '07' AND day = '16' AND hour = '14'"


def test_modo_incremental_uma_particao_falha_nao_impede_a_outra_de_rodar():
    with patch.object(transform_runner, "particoes_a_processar", return_value=PARTICOES_TESTE), \
         patch.object(
             transform_runner,
             "executar_query_sincrona",
             side_effect=[transform_runner.AthenaQueryError("falhou"), None],
         ) as mock_exec:
        with pytest.raises(RuntimeError, match=r"1 partição\(ões\) falharam"):
            transform_runner.processar_particoes("WHERE {particao_filtro}", database="silver", workgroup="wg")

    assert mock_exec.call_count == 2  # tentou as duas partições, mesmo a primeira falhando


def test_modo_incremental_todas_particoes_falham():
    with patch.object(transform_runner, "particoes_a_processar", return_value=PARTICOES_TESTE), \
         patch.object(
             transform_runner,
             "executar_query_sincrona",
             side_effect=transform_runner.AthenaQueryTimeoutError("expirou"),
         ):
        with pytest.raises(RuntimeError, match=r"2 partição\(ões\) falharam"):
            transform_runner.processar_particoes("WHERE {particao_filtro}", database="silver", workgroup="wg")


def test_modo_backfill_roda_uma_unica_vez_sem_filtro_de_particao():
    with patch.object(transform_runner, "particoes_a_processar") as mock_particoes, \
         patch.object(transform_runner, "executar_query_sincrona") as mock_exec:
        resultado = transform_runner.processar_particoes(
            "WHERE {particao_filtro}", database="silver", workgroup="wg", backfill=True
        )

    mock_particoes.assert_not_called()  # backfill não usa o cálculo de hora atual/anterior
    mock_exec.assert_called_once()
    query_enviada = mock_exec.call_args[0][0]
    assert query_enviada == "WHERE 1=1"
    assert resultado == {"statusCode": 200, "modo": "backfill"}


def test_modo_backfill_propaga_erro_sem_capturar():
    with patch.object(
        transform_runner,
        "executar_query_sincrona",
        side_effect=transform_runner.AthenaQueryError("falhou"),
    ):
        with pytest.raises(transform_runner.AthenaQueryError):
            transform_runner.processar_particoes(
                "WHERE {particao_filtro}", database="silver", workgroup="wg", backfill=True
            )
