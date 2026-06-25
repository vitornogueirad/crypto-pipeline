"""
Testes unitários da Lambda de ingestão.
Roda sem AWS real — mocka boto3 e a chamada HTTP.
"""
import json
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest


@pytest.fixture(autouse=True)
def env(monkeypatch):
    monkeypatch.setenv("RAW_BUCKET", "test-bucket")
    monkeypatch.setenv("COINGECKO_SECRET_NAME", "test-secret")
    monkeypatch.setenv("COINS", "bitcoin,ethereum")
    monkeypatch.setenv("VS_CURRENCY", "usd")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")


def _fresh_handler():
    import importlib
    import handler
    importlib.reload(handler)
    return handler


def test_build_s3_key_usa_particionamento_hive():
    handler = _fresh_handler()

    now = datetime(2026, 6, 10, 14, 30, 0, tzinfo=timezone.utc)
    key = handler._build_s3_key(now)

    assert key.startswith("bronze/coingecko/")
    assert "year=2026" in key
    assert "month=06" in key
    assert "day=10" in key
    assert "hour=14" in key
    assert key.endswith("markets_20260610T143000Z.json")


def test_handler_grava_no_s3_com_metadado():
    handler = _fresh_handler()

    fake_data = [
        {"id": "bitcoin", "current_price": 65000},
        {"id": "ethereum", "current_price": 3500},
    ]
    mock_s3 = MagicMock()

    with patch.object(handler, "_get_api_key", return_value="fake-key"), \
         patch.object(handler, "_fetch_market_data", return_value=fake_data), \
         patch.object(handler, "_client", return_value=mock_s3):

        result = handler.handler({}, None)

    assert result["statusCode"] == 200
    assert result["records"] == 2

    mock_s3.put_object.assert_called_once()
    call = mock_s3.put_object.call_args.kwargs
    assert call["Bucket"] == "test-bucket"

    body_lines = call["Body"].decode("utf-8").splitlines()
    first_record = json.loads(body_lines[0])
    assert "_ingested_at" in first_record


def test_handler_lista_vazia_nao_grava():
    handler = _fresh_handler()

    mock_s3 = MagicMock()

    with patch.object(handler, "_get_api_key", return_value="fake-key"), \
         patch.object(handler, "_fetch_market_data", return_value=[]), \
         patch.object(handler, "_client", return_value=mock_s3):

        result = handler.handler({}, None)

    assert result["statusCode"] == 204
    assert result["records"] == 0
    mock_s3.put_object.assert_not_called()
