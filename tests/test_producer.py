"""
Testes do producer.

Cobre: normalização (precisão preservada como string), partition key,
envio ao Kinesis com retry limitado, falha parcial, devolução à fila ao
esgotar retries, e backpressure (descarte quando a fila está cheia).
"""
import asyncio
import os
from unittest.mock import MagicMock, patch

import pytest

from conftest import load_module

os.environ.setdefault("KINESIS_STREAM_NAME", "test-stream")
os.environ.setdefault("AWS_REGION", "us-east-1")


def _fresh_producer():
    return load_module("binance_producer", "src/producer/binance/producer.py")


def _trade(trade_id: int, symbol: str = "BTCUSDT",
           price: str = "67800.50000001", qty: str = "0.00000001") -> dict:
    """Trade normalizado como o producer o produz (price/quantity string)."""
    return {
        "trade_id": trade_id,
        "symbol": symbol,
        "price": price,
        "quantity": qty,
        "trade_time": 1672515782136,
        "is_buyer_maker": False,
    }

def test_normalizar_preserva_precisao_como_string():
    producer = _fresh_producer()
    raw = {
        "e": "aggTrade", "s": "BTCUSDT", "a": 12345,
        "p": "67800.50000001", "q": "0.00000001", "T": 1672515782136, "m": True,
    }
    result = producer._normalizar(raw)
    assert result["trade_id"] == 12345
    assert result["symbol"] == "BTCUSDT"
    assert result["price"] == "67800.50000001"
    assert isinstance(result["price"], str)
    assert result["quantity"] == "0.00000001"
    assert isinstance(result["quantity"], str)
    assert result["trade_time"] == 1672515782136
    assert result["is_buyer_maker"] is True


def test_partition_key_distribui_por_trade():
    producer = _fresh_producer()
    k1 = producer._partition_key(_trade(1))
    k2 = producer._partition_key(_trade(2))
    assert k1 == "BTCUSDT-1"
    assert k2 == "BTCUSDT-2"
    assert k1 != k2  # evita hot shard


# Envio ao Kinesis

@pytest.mark.asyncio
async def test_enviar_lote_sucesso_na_primeira():
    producer = _fresh_producer()
    fila = asyncio.Queue()
    mock_kinesis = MagicMock()
    mock_kinesis.put_records.return_value = {"FailedRecordCount": 0, "Records": [{}]}

    with patch.object(producer, "_kinesis", mock_kinesis):
        await producer._enviar_lote([_trade(1)], fila)

    assert mock_kinesis.put_records.call_count == 1
    assert fila.empty()  # nada devolvido


@pytest.mark.asyncio
async def test_partition_key_vai_no_record_enviado():
    """Garante que o PartitionKey enviado ao Kinesis é symbol-tradeId."""
    producer = _fresh_producer()
    fila = asyncio.Queue()
    mock_kinesis = MagicMock()
    mock_kinesis.put_records.return_value = {"FailedRecordCount": 0, "Records": [{}]}

    with patch.object(producer, "_kinesis", mock_kinesis):
        await producer._enviar_lote([_trade(1)], fila)

    records = mock_kinesis.put_records.call_args.kwargs["Records"]
    assert records[0]["PartitionKey"] == "BTCUSDT-1"


@pytest.mark.asyncio
async def test_falha_parcial_retenta_so_os_falhos():
    """1ª chamada: registro 2 falha. 2ª chamada: só ele é reenviado e passa."""
    producer = _fresh_producer()
    producer.RETRY_BACKOFF_SEC = 0
    fila = asyncio.Queue()
    mock_kinesis = MagicMock()
    mock_kinesis.put_records.side_effect = [
        {"FailedRecordCount": 1, "Records": [{}, {"ErrorCode": "Throttling"}]},
        {"FailedRecordCount": 0, "Records": [{}]},
    ]

    with patch.object(producer, "_kinesis", mock_kinesis):
        await producer._enviar_lote([_trade(1), _trade(2)], fila)

    assert mock_kinesis.put_records.call_count == 2
    segunda = mock_kinesis.put_records.call_args_list[1].kwargs["Records"]
    assert len(segunda) == 1  # só o falho foi reenviado
    assert fila.empty()


@pytest.mark.asyncio
async def test_esgotar_retries_devolve_para_fila():
    """MAX_RETRIES falhas → trades devolvidos à fila, loop liberado."""
    producer = _fresh_producer()
    producer.RETRY_BACKOFF_SEC = 0
    producer.MAX_RETRIES = 2
    fila = asyncio.Queue()
    mock_kinesis = MagicMock()
    mock_kinesis.put_records.return_value = {
        "FailedRecordCount": 1, "Records": [{"ErrorCode": "Throttling"}]
    }

    with patch.object(producer, "_kinesis", mock_kinesis):
        await producer._enviar_lote([_trade(9)], fila)

    assert mock_kinesis.put_records.call_count == 2  # exatamente MAX_RETRIES
    assert fila.qsize() == 1
    assert fila.get_nowait()["trade_id"] == 9


@pytest.mark.asyncio
async def test_erro_total_retenta_lote_inteiro():
    """Exceção na chamada (rede) → retry do lote completo, com teto."""
    producer = _fresh_producer()
    producer.RETRY_BACKOFF_SEC = 0
    producer.MAX_RETRIES = 3
    fila = asyncio.Queue()
    mock_kinesis = MagicMock()
    mock_kinesis.put_records.side_effect = [
        ConnectionError("rede caiu"),
        ConnectionError("rede caiu"),
        {"FailedRecordCount": 0, "Records": [{}]},  # 3ª tentativa passa
    ]

    with patch.object(producer, "_kinesis", mock_kinesis):
        await producer._enviar_lote([_trade(5)], fila)

    assert mock_kinesis.put_records.call_count == 3
    assert fila.empty()


@pytest.mark.asyncio
async def test_fila_cheia_no_reenfileiramento_descarta():
    """
    Backpressure explícito: se a fila está cheia ao devolver os trades
    (retries esgotados), o trade é descartado com log — não trava o loop.
    """
    producer = _fresh_producer()
    producer.RETRY_BACKOFF_SEC = 0
    producer.MAX_RETRIES = 1
    fila = asyncio.Queue(maxsize=1)
    fila.put_nowait(_trade(100))  # enche a fila (só cabe 1)

    mock_kinesis = MagicMock()
    mock_kinesis.put_records.return_value = {
        "FailedRecordCount": 1, "Records": [{"ErrorCode": "Throttling"}]
    }

    with patch.object(producer, "_kinesis", mock_kinesis):
        # não deve levantar exceção mesmo com a fila cheia
        await producer._enviar_lote([_trade(200)], fila)

    # a fila continua com o item original; o novo foi descartado (backpressure)
    assert fila.qsize() == 1
    assert fila.get_nowait()["trade_id"] == 100
