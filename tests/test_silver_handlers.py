"""
Testes dos handlers Lambda que disparam o MERGE INTO da silver.
Roda sem AWS real — mocka processar_particoes.
"""
from unittest.mock import MagicMock, patch

import pytest

from conftest import load_module


@pytest.fixture(autouse=True)
def env(monkeypatch):
    monkeypatch.setenv("ATHENA_WORKGROUP", "crypto-pipeline-silver-gold")
    monkeypatch.setenv("SILVER_DATABASE", "silver")


def test_trades_handler_modo_incremental_por_padrao():
    handler_module = load_module("trades_handler", "src/transform/silver/trades_handler.py")

    with patch.object(handler_module, "processar_particoes", return_value={"statusCode": 200}) as mock_run:
        resultado = handler_module.handler({}, MagicMock())

    _, kwargs = mock_run.call_args
    assert kwargs["backfill"] is False
    assert kwargs["database"] == "silver"
    assert kwargs["workgroup"] == "crypto-pipeline-silver-gold"
    assert resultado == {"statusCode": 200}


def test_trades_handler_repassa_backfill_do_evento():
    handler_module = load_module("trades_handler", "src/transform/silver/trades_handler.py")

    with patch.object(handler_module, "processar_particoes", return_value={"statusCode": 200}) as mock_run:
        handler_module.handler({"backfill": True}, MagicMock())

    assert mock_run.call_args.kwargs["backfill"] is True


def test_trades_handler_evento_none_nao_quebra():
    handler_module = load_module("trades_handler", "src/transform/silver/trades_handler.py")

    with patch.object(handler_module, "processar_particoes", return_value={"statusCode": 200}) as mock_run:
        handler_module.handler(None, MagicMock())

    assert mock_run.call_args.kwargs["backfill"] is False


def test_market_snapshot_handler_modo_incremental_por_padrao():
    handler_module = load_module("market_snapshot_handler", "src/transform/silver/market_snapshot_handler.py")

    with patch.object(handler_module, "processar_particoes", return_value={"statusCode": 200}) as mock_run:
        resultado = handler_module.handler({}, MagicMock())

    _, kwargs = mock_run.call_args
    assert kwargs["backfill"] is False
    assert kwargs["database"] == "silver"
    assert resultado == {"statusCode": 200}


def test_market_snapshot_handler_repassa_backfill_do_evento():
    handler_module = load_module("market_snapshot_handler", "src/transform/silver/market_snapshot_handler.py")

    with patch.object(handler_module, "processar_particoes", return_value={"statusCode": 200}) as mock_run:
        handler_module.handler({"backfill": True}, MagicMock())

    assert mock_run.call_args.kwargs["backfill"] is True
