-- ══════════════════════════════════════════════════════════════════
-- crypto-pipeline — Transform: bronze.coingecko → silver.market_snapshot
--
-- Mesmo padrão do silver_trades_merge.sql: template carregado e
-- parametrizado pela Lambda via {particao_filtro} — não executado
-- manualmente. Suporta modo incremental (filtro por hora) e modo
-- backfill ({particao_filtro} = "1=1", tabela inteira de uma vez).
--
-- Chave natural do MERGE (id, last_updated): dedup contra
-- reprocessamento/retry da Lambda de ingestão batch, não contra
-- duplicidade "de negócio" (cada linha já é um snapshot único por
-- definição da API).
-- ══════════════════════════════════════════════════════════════════

MERGE INTO silver.market_snapshot AS target
USING (
    SELECT
        id,
        symbol,
        upper(symbol) AS asset_symbol,
        name,
        CAST(current_price AS DECIMAL(38,8))                           AS current_price,
        CAST(market_cap AS DECIMAL(38,8))                              AS market_cap,
        market_cap_rank,
        CAST(fully_diluted_valuation AS DECIMAL(38,8))                 AS fully_diluted_valuation,
        CAST(total_volume AS DECIMAL(38,8))                            AS total_volume,
        CAST(high_24h AS DECIMAL(38,8))                                AS high_24h,
        CAST(low_24h AS DECIMAL(38,8))                                 AS low_24h,
        CAST(price_change_24h AS DECIMAL(38,8))                        AS price_change_24h,
        CAST(price_change_percentage_24h AS DECIMAL(18,8))             AS price_change_percentage_24h,
        CAST(market_cap_change_24h AS DECIMAL(38,8))                   AS market_cap_change_24h,
        CAST(market_cap_change_percentage_24h AS DECIMAL(18,8))        AS market_cap_change_percentage_24h,
        CAST(circulating_supply AS DECIMAL(38,8))                      AS circulating_supply,
        CAST(total_supply AS DECIMAL(38,8))                            AS total_supply,
        CAST(max_supply AS DECIMAL(38,8))                              AS max_supply,
        CAST(ath AS DECIMAL(38,8))                                     AS ath,
        CAST(ath_change_percentage AS DECIMAL(18,8))                   AS ath_change_percentage,
        from_iso8601_timestamp(ath_date)                               AS ath_date,
        CAST(atl AS DECIMAL(38,8))                                     AS atl,
        CAST(atl_change_percentage AS DECIMAL(18,8))                   AS atl_change_percentage,
        from_iso8601_timestamp(atl_date)                               AS atl_date,
        from_iso8601_timestamp(last_updated)                           AS last_updated,
        CAST(price_change_percentage_1h_in_currency AS DECIMAL(18,8))  AS price_change_percentage_1h_in_currency,
        CAST(price_change_percentage_24h_in_currency AS DECIMAL(18,8)) AS price_change_percentage_24h_in_currency,
        CAST(price_change_percentage_7d_in_currency AS DECIMAL(18,8))  AS price_change_percentage_7d_in_currency,
        from_iso8601_timestamp(COALESCE(ingested_at, _ingested_at))    AS ingested_at
    FROM bronze.coingecko
    WHERE {particao_filtro}
) AS source
ON target.id = source.id AND target.last_updated = source.last_updated
WHEN NOT MATCHED THEN
    INSERT (id, symbol, asset_symbol, name, current_price, market_cap, market_cap_rank,
            fully_diluted_valuation, total_volume, high_24h, low_24h, price_change_24h,
            price_change_percentage_24h, market_cap_change_24h, market_cap_change_percentage_24h,
            circulating_supply, total_supply, max_supply, ath, ath_change_percentage, ath_date,
            atl, atl_change_percentage, atl_date, last_updated,
            price_change_percentage_1h_in_currency, price_change_percentage_24h_in_currency,
            price_change_percentage_7d_in_currency, ingested_at)
    VALUES (source.id, source.symbol, source.asset_symbol, source.name, source.current_price,
            source.market_cap, source.market_cap_rank, source.fully_diluted_valuation,
            source.total_volume, source.high_24h, source.low_24h, source.price_change_24h,
            source.price_change_percentage_24h, source.market_cap_change_24h,
            source.market_cap_change_percentage_24h, source.circulating_supply, source.total_supply,
            source.max_supply, source.ath, source.ath_change_percentage, source.ath_date,
            source.atl, source.atl_change_percentage, source.atl_date, source.last_updated,
            source.price_change_percentage_1h_in_currency, source.price_change_percentage_24h_in_currency,
            source.price_change_percentage_7d_in_currency, source.ingested_at);