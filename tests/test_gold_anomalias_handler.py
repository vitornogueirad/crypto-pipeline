"""
Testes do handler Lambda que recalcula gold.anomalias.
Roda sem AWS real — mocka executar_query_sincrona.
"""
from unittest.mock import MagicMock, patch

import pytest

from conftest import load_module


@pytest.fixture(autouse=True)
def env(monkeypatch):
    monkeypatch.setenv("ATHENA_WORKGROUP", "crypto-pipeline-silver-gold")
    monkeypatch.setenv("GOLD_DATABASE", "gold")


def test_handler_executa_merge_no_database_gold():
    handler_module = load_module("anomalias_handler", "src/transform/gold/anomalias_handler.py")

    with patch.object(handler_module, "executar_query_sincrona", return_value="exec-id-123") as mock_exec:
        resultado = handler_module.handler({}, MagicMock())

    mock_exec.assert_called_once()
    query_usada, kwargs = mock_exec.call_args[0][0], mock_exec.call_args[1]
    assert "MERGE INTO gold.anomalias" in query_usada
    assert kwargs["database"] == "gold"
    assert kwargs["workgroup"] == "crypto-pipeline-silver-gold"
    assert resultado == {"statusCode": 200}


def test_handler_nao_precisa_de_particao_no_event():
    handler_module = load_module("anomalias_handler", "src/transform/gold/anomalias_handler.py")

    with patch.object(handler_module, "executar_query_sincrona", return_value="exec-id-123"):
        # Não levanta erro mesmo com event vazio — gold não usa particao_filtro
        resultado = handler_module.handler(None, MagicMock())

    assert resultado == {"statusCode": 200}


def test_handler_propaga_erro_da_query():
    handler_module = load_module("anomalias_handler", "src/transform/gold/anomalias_handler.py")

    with patch.object(handler_module, "executar_query_sincrona", side_effect=Exception("falhou")):
        with pytest.raises(Exception, match="falhou"):
            handler_module.handler({}, MagicMock())
