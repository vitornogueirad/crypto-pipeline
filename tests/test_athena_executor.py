"""
Testes do executor síncrono de queries no Athena.
Roda sem AWS real — mocka o client boto3.
"""
from unittest.mock import MagicMock

import pytest

from conftest import load_module

athena_executor = load_module("athena_executor", "src/transform/common/athena_executor.py")


def _client_com_estados(estados):
    """Client mock cujo get_query_execution retorna estados sucessivos, um por chamada."""
    client = MagicMock()
    client.start_query_execution.return_value = {"QueryExecutionId": "abc-123"}
    client.get_query_execution.side_effect = [
        {"QueryExecution": {"Status": {"State": estado, "StateChangeReason": "erro simulado"}}}
        for estado in estados
    ]
    return client


def test_query_sucesso_na_primeira_checagem(monkeypatch):
    monkeypatch.setattr(athena_executor.time, "sleep", lambda _: None)
    client = _client_com_estados(["SUCCEEDED"])

    execution_id = athena_executor.executar_query_sincrona(
        "SELECT 1", database="silver", workgroup="wg-teste", client=client
    )

    assert execution_id == "abc-123"
    client.start_query_execution.assert_called_once()


def test_query_demora_mas_sucede(monkeypatch):
    monkeypatch.setattr(athena_executor.time, "sleep", lambda _: None)
    client = _client_com_estados(["QUEUED", "RUNNING", "RUNNING", "SUCCEEDED"])

    execution_id = athena_executor.executar_query_sincrona(
        "SELECT 1", database="silver", workgroup="wg-teste", client=client
    )

    assert execution_id == "abc-123"
    assert client.get_query_execution.call_count == 4


def test_query_falha_levanta_erro(monkeypatch):
    monkeypatch.setattr(athena_executor.time, "sleep", lambda _: None)
    client = _client_com_estados(["FAILED"])

    with pytest.raises(athena_executor.AthenaQueryError, match="erro simulado"):
        athena_executor.executar_query_sincrona(
            "SELECT 1", database="silver", workgroup="wg-teste", client=client
        )


def test_query_cancelada_levanta_erro(monkeypatch):
    monkeypatch.setattr(athena_executor.time, "sleep", lambda _: None)
    client = _client_com_estados(["CANCELLED"])

    with pytest.raises(athena_executor.AthenaQueryError):
        athena_executor.executar_query_sincrona(
            "SELECT 1", database="silver", workgroup="wg-teste", client=client
        )


def test_query_expira_apos_max_tentativas(monkeypatch):
    monkeypatch.setattr(athena_executor.time, "sleep", lambda _: None)
    monkeypatch.setattr(athena_executor, "MAX_POLL_ATTEMPTS", 3)
    client = _client_com_estados(["RUNNING", "RUNNING", "RUNNING"])

    with pytest.raises(athena_executor.AthenaQueryTimeoutError):
        athena_executor.executar_query_sincrona(
            "SELECT 1", database="silver", workgroup="wg-teste", client=client
        )
