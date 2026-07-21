-- ══════════════════════════════════════════════════════════════════
-- crypto-pipeline — Transform: silver.trades + silver.market_snapshot
-- → gold.anomalias
--
-- Corpo da Lambda de gold (anomalias_handler.py). Sem parametrização
-- de partição — diferente da silver, o baseline móvel de 6h é window
-- function e precisa da tabela inteira em cada execução.
--
-- WHEN MATCHED THEN UPDATE (não só INSERT): uma janela já calculada
-- pode ter o z_score revisado se chegar snapshot novo do CoinGecko
-- que mude o baseline dela. Trade é imutável (silver não faz UPDATE);
-- o resultado agregado da gold não é — é upsert de verdade.
-- ══════════════════════════════════════════════════════════════════

MERGE INTO gold.anomalias AS target
USING (
    WITH baseline_movel AS (
        SELECT
            asset_symbol,
            ingested_at,
            current_price,
            AVG(current_price) OVER (
                PARTITION BY asset_symbol
                ORDER BY ingested_at
                RANGE BETWEEN INTERVAL '6' HOUR PRECEDING AND CURRENT ROW
            ) AS baseline_media,
            STDDEV(current_price) OVER (
                PARTITION BY asset_symbol
                ORDER BY ingested_at
                RANGE BETWEEN INTERVAL '6' HOUR PRECEDING AND CURRENT ROW
            ) AS baseline_desvio
        FROM silver.market_snapshot
    ),

    trades_agregados AS (
        SELECT
            asset_symbol,
            from_unixtime(floor(to_unixtime(trade_time) / 600) * 600)       AS janela_inicio,
            from_unixtime(floor(to_unixtime(trade_time) / 600) * 600 + 600) AS janela_fim,
            SUM(price * quantity) / SUM(quantity) AS preco_vwap,
            SUM(quantity)                         AS volume_total,
            COUNT(*)                              AS qtd_trades
        FROM silver.trades
        GROUP BY
            asset_symbol,
            from_unixtime(floor(to_unixtime(trade_time) / 600) * 600),
            from_unixtime(floor(to_unixtime(trade_time) / 600) * 600 + 600)
    ),

    trades_com_baseline_ranqueado AS (
        SELECT
            t.*,
            b.baseline_media,
            b.baseline_desvio,
            ROW_NUMBER() OVER (
                PARTITION BY t.asset_symbol, t.janela_inicio
                ORDER BY b.ingested_at DESC
            ) AS rn
        FROM trades_agregados t
        LEFT JOIN baseline_movel b
            ON b.asset_symbol = t.asset_symbol
            AND b.ingested_at <= t.janela_fim
    )

    SELECT
        asset_symbol,
        janela_inicio,
        janela_fim,
        preco_vwap,
        volume_total,
        qtd_trades,
        baseline_media,
        baseline_desvio,
        (preco_vwap - baseline_media) / baseline_desvio AS z_score,
        CASE
            WHEN ABS((preco_vwap - baseline_media) / baseline_desvio) > 3 THEN true
            ELSE false
        END AS anomalia
    FROM trades_com_baseline_ranqueado
    WHERE rn = 1
      AND baseline_desvio > 0
) AS source
ON target.asset_symbol = source.asset_symbol AND target.janela_inicio = source.janela_inicio
WHEN MATCHED THEN UPDATE SET
    janela_fim      = source.janela_fim,
    preco_vwap      = source.preco_vwap,
    volume_total    = source.volume_total,
    qtd_trades      = source.qtd_trades,
    baseline_media  = source.baseline_media,
    baseline_desvio = source.baseline_desvio,
    z_score         = source.z_score,
    anomalia        = source.anomalia
WHEN NOT MATCHED THEN INSERT (
    asset_symbol, janela_inicio, janela_fim, preco_vwap, volume_total,
    qtd_trades, baseline_media, baseline_desvio, z_score, anomalia
) VALUES (
    source.asset_symbol, source.janela_inicio, source.janela_fim, source.preco_vwap,
    source.volume_total, source.qtd_trades, source.baseline_media, source.baseline_desvio,
    source.z_score, source.anomalia
);
