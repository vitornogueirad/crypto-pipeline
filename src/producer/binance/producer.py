"""
Producer — lê o stream @aggTrade da Binance (WebSocket) e publica no Kinesis.

Arquitetura async produtor-consumidor:
  - `receber_trades`: coroutine que só lê do WebSocket e enfileira
  - `enviar_para_kinesis`: coroutine que drena a fila em lotes e envia via put_records

Confiabilidade do envio:
  - put_records roda em thread (asyncio.to_thread): boto3 é síncrono e, sem
    isso, cada chamada de rede congelaria o event loop inteiro — inclusive
    a leitura do WebSocket.
  - Falha parcial: retry com backoff limitado (MAX_RETRIES) dos registros
    que falharam. Esgotou: devolve à fila principal e libera o loop de envio
    (não bloqueia novos lotes num retry eterno).
  - Fila cheia ao devolver: descarta com log (backpressure explícito).

Roda sob demanda (local ou container). Não fica 24/7 na nuvem — decisão de custo.
"""
import asyncio
import json
import logging
import os
import signal

import boto3
import websockets

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("producer")

# ── Configuração (via env) ──────────────────────────────────────────
STREAM_NAME = os.environ["KINESIS_STREAM_NAME"]
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
SYMBOLS = os.environ.get("SYMBOLS", "btcusdt,ethusdt,solusdt,adausdt").split(",")

BINANCE_WS_BASE = "wss://data-stream.binance.vision/stream?streams="

FLUSH_SIZE = 500
FLUSH_INTERVAL_SEC = 2.0
MAX_QUEUE = 10000
MAX_RETRIES = 3
RETRY_BACKOFF_SEC = 0.5

_kinesis = boto3.client("kinesis", region_name=AWS_REGION)
_shutdown = asyncio.Event()


def _normalizar(raw: dict) -> dict:
    """Payload cru do @aggTrade → schema limpo"""
    return {
        "trade_id": raw["a"],
        "symbol": raw["s"],
        "price": raw["p"],
        "quantity": raw["q"],
        "trade_time": raw["T"],
        "is_buyer_maker": raw["m"],
    }


def _partition_key(trade: dict) -> str:
    """symbol-aggTradeId: distribui entre shards, evita hot shard no BTC."""
    return f"{trade['symbol']}-{trade['trade_id']}"


async def receber_trades(fila: asyncio.Queue) -> None:
    """Lê do WebSocket e enfileira. Reconecta em caso de queda."""
    streams = "/".join(f"{s}@aggTrade" for s in SYMBOLS)
    url = BINANCE_WS_BASE + streams

    backoff = 1
    while not _shutdown.is_set():
        try:
            async with websockets.connect(url, ping_interval=180, ping_timeout=600) as ws:
                logger.info("Conectado ao WebSocket: %s símbolos", len(SYMBOLS))
                backoff = 1
                async for mensagem in ws:
                    if _shutdown.is_set():
                        break
                    envelope = json.loads(mensagem)
                    raw = envelope.get("data", envelope)
                    if raw.get("e") != "aggTrade":
                        continue
                    try:
                        fila.put_nowait(_normalizar(raw))
                    except asyncio.QueueFull:
                        logger.warning("Fila cheia — descartando trade (Kinesis lento?)")
        except (websockets.ConnectionClosed, OSError) as exc:
            if _shutdown.is_set():
                break
            logger.warning("Conexão caiu (%s). Reconectando em %ds...", exc, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 60)


def _put_records_sync(records: list[dict]) -> dict:
    """Chamada boto3 síncrona — executada via to_thread para não travar o loop."""
    return _kinesis.put_records(StreamName=STREAM_NAME, Records=records)


async def _enviar_lote(lote: list[dict], fila: asyncio.Queue) -> None:
    """
    Envia um lote com retry limitado. 
    Regras:
      - boto3 roda em thread (não bloqueia o event loop)
      - falha parcial: retenta só os registros falhos, com backoff, até MAX_RETRIES
      - esgotou os retries: devolve os falhos à fila principal
        (libera o loop de envio para drenar novos trades)
    """
    pendentes = lote

    for tentativa in range(1, MAX_RETRIES + 1):
        if not pendentes:
            return

        records = [
            {"Data": json.dumps(t).encode("utf-8"), "PartitionKey": _partition_key(t)}
            for t in pendentes
        ]

        try:
            resp = await asyncio.to_thread(_put_records_sync, records)
        except Exception as exc:  # noqa: BLE001 — erro total (rede, throttling do stream)
            logger.warning("put_records falhou por inteiro (%s), tentativa %d/%d",
                           exc, tentativa, MAX_RETRIES)
            await asyncio.sleep(RETRY_BACKOFF_SEC * (2 ** (tentativa - 1)))
            continue  # pendentes inalterado: retenta o lote todo

        if resp.get("FailedRecordCount", 0) == 0:
            logger.info("Enviados %d trades ao Kinesis", len(pendentes))
            return

        # falha PARCIAL: isola só os que falharam
        pendentes = [
            pendentes[i]
            for i, r in enumerate(resp["Records"])
            if r.get("ErrorCode")
        ]
        logger.warning("%d registros falharam (tentativa %d/%d)",
                       len(pendentes), tentativa, MAX_RETRIES)
        await asyncio.sleep(RETRY_BACKOFF_SEC * (2 ** (tentativa - 1)))

    # esgotou os retries: devolve à fila e libera o loop de envio
    devolvidos = 0
    for trade in pendentes:
        try:
            fila.put_nowait(trade)
            devolvidos += 1
        except asyncio.QueueFull:
            logger.error("Fila cheia no reenfileiramento — trade %s descartado", trade.get("trade_id"))
    logger.warning("Retries esgotados: %d/%d trades devolvidos à fila",
                   devolvidos, len(pendentes))


async def enviar_para_kinesis(fila: asyncio.Queue) -> None:
    """Drena a fila em lotes (por tamanho ou tempo) e envia ao Kinesis."""
    while not _shutdown.is_set() or not fila.empty():
        lote = []
        try:
            primeiro = await asyncio.wait_for(fila.get(), timeout=FLUSH_INTERVAL_SEC)
            lote.append(primeiro)
            while len(lote) < FLUSH_SIZE:
                try:
                    lote.append(fila.get_nowait())
                except asyncio.QueueEmpty:
                    break
        except asyncio.TimeoutError:
            pass

        if lote:
            await _enviar_lote(lote, fila)


def _tratar_sinal():
    logger.info("Sinal de parada recebido, encerrando graciosamente...")
    _shutdown.set()


async def main():
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _tratar_sinal)
        except NotImplementedError:
            pass  # Evita quebra se rodar no Windows localmente

    fila: asyncio.Queue = asyncio.Queue(maxsize=MAX_QUEUE)

    # Transformamos as corrotinas em Tarefas (Tasks) gerenciadas pelo loop
    tarefa_produtor = asyncio.create_task(receber_trades(fila))
    tarefa_consumidor = asyncio.create_task(enviar_para_kinesis(fila))

    done, pending = await asyncio.wait(
        [tarefa_produtor, tarefa_consumidor],
        return_when=asyncio.FIRST_COMPLETED
    )

    if not _shutdown.is_set():
        logger.critical("Uma das tarefas principais encerrou inesperadamente! Forçando parada geral...")
        _shutdown.set()

    if pending:
        logger.info("Aguardando finalização da tarefa restante...")
        await asyncio.gather(*pending, return_exceptions=True)

    logger.info("Producer encerrado de forma segura.")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Producer interrompido pelo usuário (Ctrl+C).")