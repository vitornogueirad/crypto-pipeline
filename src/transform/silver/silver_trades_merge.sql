-- ══════════════════════════════════════════════════════════════════
-- crypto-pipeline — Transform: bronze.trades → silver.trades
--
-- Não é executado manualmente. É o template que a Lambda de
-- transformação carrega, substitui {particao_filtro} pelo filtro
-- da invocação atual (string .format() no Python, não bind
-- parameter do Athena — Athena não tem parâmetro nomeado nesse formato)
-- e envia via athena.start_query_execution().
--
-- Modo incremental (padrão): {particao_filtro} = "year = 'X' AND
-- month = 'X' AND day = 'X' AND hour = 'X'", processando hora atual
-- e hora anterior a cada invocação.
-- Modo backfill: {particao_filtro} = "1=1", processando a tabela
-- bronze inteira de uma vez (usado pra carregar dado histórico que já
-- existia antes da Lambda começar a rodar).
--
-- MERGE INTO com WHEN NOT MATCHED garante idempotência: reprocessar a
-- mesma partição (ou a tabela inteira, no backfill) não duplica linha.
-- ══════════════════════════════════════════════════════════════════

MERGE INTO silver.trades AS target
USING (
    SELECT
        trade_id,
        symbol,
        regexp_replace(symbol, 'USDT$', '') AS asset_symbol,
        CAST(price AS DECIMAL(38,8))        AS price,
        CAST(quantity AS DECIMAL(38,8))     AS quantity,
        from_unixtime(trade_time / 1000.0)  AS trade_time,
        is_buyer_maker,
        from_iso8601_timestamp(COALESCE(ingested_at, _ingested_at)) AS ingested_at
    FROM bronze.trades
    WHERE {particao_filtro}
) AS source
ON target.trade_id = source.trade_id
WHEN NOT MATCHED THEN
    INSERT (trade_id, symbol, asset_symbol, price, quantity, trade_time, is_buyer_maker, ingested_at)
    VALUES (source.trade_id, source.symbol, source.asset_symbol, source.price, source.quantity, source.trade_time, source.is_buyer_maker, source.ingested_at);