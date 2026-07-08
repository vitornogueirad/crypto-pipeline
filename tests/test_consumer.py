"""
Testes do consumer. Mocka DynamoDB e S3.
Cobre: dedup memória/DynamoDB, 1 arquivo por batch, falhas parciais,
rollback quando o S3 falha e preservação de precisão (string).
"""
import base64
import json
from unittest.mock import MagicMock, patch
 
import pytest
 
from conftest import load_module
from botocore.exceptions import ClientError
 
 
@pytest.fixture(autouse=True)
def env(monkeypatch):
    monkeypatch.setenv("RAW_BUCKET", "test-bucket")
    monkeypatch.setenv("DEDUP_TABLE", "test-dedup")
    monkeypatch.setenv("DEDUP_TTL_HOURS", "6")
    monkeypatch.setenv("DEDUP_MAX_WORKERS", "5")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
 
 
def _fresh_handler():
    return load_module("consumer_handler", "src/consumer/trades/handler.py")
 
 
def _trade(trade_id: int, price: str = "67800.50000001", qty: str = "0.00000001") -> dict:
    """Trade no schema real que o producer envia (price/quantity como string)."""
    return {
        "trade_id": trade_id,
        "symbol": "BTCUSDT",
        "price": price,
        "quantity": qty,
        "trade_time": 1672515782136,
        "is_buyer_maker": False,
    }
 
 
def _rec(trade: dict, seq: str = "seq-1"):
    data = base64.b64encode(json.dumps(trade).encode("utf-8")).decode("utf-8")
    return {"kinesis": {"data": data, "sequenceNumber": seq}}
 
 
class _Ctx:
    aws_request_id = "req-abc"
 
 
def _mocks():
    """Helper: retorna (mock_dynamo, mock_table, mock_s3) já ligados."""
    mock_table = MagicMock()
    mock_dynamo = MagicMock()
    mock_dynamo.Table.return_value = mock_table
    mock_s3 = MagicMock()
    return mock_dynamo, mock_table, mock_s3
 
 
def test_build_s3_key_um_arquivo_por_batch():
    from datetime import datetime, timezone
    handler = _fresh_handler()
    now = datetime(2026, 6, 10, 14, 30, 0, tzinfo=timezone.utc)
    key = handler._build_s3_key(now, "req-abc")
    assert key.startswith("bronze/trades/")
    assert "year=2026" in key
    assert "month=06" in key
    assert "day=10" in key
    assert "hour=14" in key
    assert key.endswith("_req-abc.jsonl")
 
 
def test_batch_grava_um_unico_arquivo():
    """3 trades novos → 1 único put_object com 3 linhas."""
    handler = _fresh_handler()
    trades = [_rec(_trade(1), "s1"), _rec(_trade(2), "s2"), _rec(_trade(3), "s3")]
    mock_dynamo, _, mock_s3 = _mocks()
 
    with patch.object(handler, "_resource", lambda s: mock_dynamo), \
         patch.object(handler, "_client", lambda s: mock_s3):
        result = handler.handler({"Records": trades}, _Ctx())
 
    assert mock_s3.put_object.call_count == 1
    body = mock_s3.put_object.call_args.kwargs["Body"].decode("utf-8")
    assert len(body.splitlines()) == 3
    assert result["batchItemFailures"] == []
 
 
def test_precisao_preservada_ate_o_s3():
    """price/quantity string devem chegar ao S3 sem virar float."""
    handler = _fresh_handler()
    trade = _trade(1, price="67800.50000001", qty="0.00000001")
    mock_dynamo, _, mock_s3 = _mocks()
 
    with patch.object(handler, "_resource", lambda s: mock_dynamo), \
         patch.object(handler, "_client", lambda s: mock_s3):
        handler.handler({"Records": [_rec(trade, "s1")]}, _Ctx())
 
    body = mock_s3.put_object.call_args.kwargs["Body"].decode("utf-8")
    gravado = json.loads(body.splitlines()[0])
    # continua string, valor exato — sem perda de precisão
    assert gravado["price"] == "67800.50000001"
    assert isinstance(gravado["price"], str)
    assert gravado["quantity"] == "0.00000001"
    assert isinstance(gravado["quantity"], str)
 
 
def test_dedup_em_memoria_nao_chama_dynamodb_para_repetidos():
    """Mesmo trade_id 3x no batch → só 1 chamada ao DynamoDB."""
    handler = _fresh_handler()
    trades = [_rec(_trade(42), "s1"), _rec(_trade(42), "s2"), _rec(_trade(42), "s3")]
    mock_dynamo, mock_table, mock_s3 = _mocks()
 
    with patch.object(handler, "_resource", lambda s: mock_dynamo), \
         patch.object(handler, "_client", lambda s: mock_s3):
        result = handler.handler({"Records": trades}, _Ctx())
 
    assert mock_table.put_item.call_count == 1
    body = mock_s3.put_object.call_args.kwargs["Body"].decode("utf-8")
    assert len(body.splitlines()) == 1
    assert result["batchItemFailures"] == []
 
 
def test_duplicado_entre_invocacoes_nao_entra_no_arquivo():
    """ConditionalCheckFailed (já processado antes) → trade ignorado."""
    handler = _fresh_handler()
    mock_dynamo, mock_table, mock_s3 = _mocks()
    mock_table.put_item.side_effect = [
        None,
        ClientError({"Error": {"Code": "ConditionalCheckFailedException"}}, "PutItem"),
    ]
    trades = [_rec(_trade(1), "s1"), _rec(_trade(2), "s2")]
 
    with patch.object(handler, "_resource", lambda s: mock_dynamo), \
         patch.object(handler, "_client", lambda s: mock_s3):
        result = handler.handler({"Records": trades}, _Ctx())
 
    body = mock_s3.put_object.call_args.kwargs["Body"].decode("utf-8")
    assert len(body.splitlines()) == 1
    assert result["batchItemFailures"] == []
 
 
def test_erro_no_dedup_vira_falha_parcial():
    """Erro real do DynamoDB (não ConditionalCheck) → registro reprocessado."""
    handler = _fresh_handler()
    mock_dynamo, mock_table, mock_s3 = _mocks()
    mock_table.put_item.side_effect = ClientError(
        {"Error": {"Code": "ProvisionedThroughputExceededException"}}, "PutItem"
    )
 
    with patch.object(handler, "_resource", lambda s: mock_dynamo), \
         patch.object(handler, "_client", lambda s: mock_s3):
        result = handler.handler({"Records": [_rec(_trade(7), "s7")]}, _Ctx())
 
    assert result["batchItemFailures"] == [{"itemIdentifier": "s7"}]
    mock_s3.put_object.assert_not_called()
 
 
def test_registro_invalido_vira_falha_parcial():
    """Payload não-decodificável vira falha parcial; o válido é gravado."""
    handler = _fresh_handler()
    bom = _rec(_trade(1), "s-bom")
    ruim = {"kinesis": {"data": base64.b64encode(b"quebrado").decode(), "sequenceNumber": "s-ruim"}}
    mock_dynamo, _, mock_s3 = _mocks()
 
    with patch.object(handler, "_resource", lambda s: mock_dynamo), \
         patch.object(handler, "_client", lambda s: mock_s3):
        result = handler.handler({"Records": [bom, ruim]}, _Ctx())
 
    assert result["batchItemFailures"] == [{"itemIdentifier": "s-ruim"}]
    assert mock_s3.put_object.call_count == 1
 
 
def test_sem_trades_novos_nao_grava():
    """Batch todo duplicado → nenhum arquivo."""
    handler = _fresh_handler()
    mock_dynamo, mock_table, mock_s3 = _mocks()
    mock_table.put_item.side_effect = ClientError(
        {"Error": {"Code": "ConditionalCheckFailedException"}}, "PutItem"
    )
 
    with patch.object(handler, "_resource", lambda s: mock_dynamo), \
         patch.object(handler, "_client", lambda s: mock_s3):
        result = handler.handler({"Records": [_rec(_trade(1))]}, _Ctx())
 
    mock_s3.put_object.assert_not_called()
    assert result["batchItemFailures"] == []
 
 
def test_falha_no_s3_desfaz_marcas_de_dedup():
    """
    S3 falha → delete_item nas marcas + batch inteiro falha.
    Sem isso, o retry veria os IDs como duplicados e os trades sumiriam.
    """
    handler = _fresh_handler()
    trades = [_rec(_trade(1), "s1"), _rec(_trade(2), "s2")]
    mock_dynamo, mock_table, mock_s3 = _mocks()
    mock_s3.put_object.side_effect = Exception("S3 indisponível")
 
    with patch.object(handler, "_resource", lambda s: mock_dynamo), \
         patch.object(handler, "_client", lambda s: mock_s3):
        result = handler.handler({"Records": trades}, _Ctx())
 
    assert mock_table.delete_item.call_count == 2
    ids_deletados = {c.kwargs["Key"]["trade_id"] for c in mock_table.delete_item.call_args_list}
    assert ids_deletados == {"1", "2"}
    assert result["batchItemFailures"] == [
        {"itemIdentifier": "s1"},
        {"itemIdentifier": "s2"},
    ]
