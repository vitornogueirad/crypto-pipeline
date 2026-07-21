-- ══════════════════════════════════════════════════════════════════
-- crypto-pipeline — DDL da silver (tabelas Iceberg)
-- Rodar MANUALMENTE, uma vez, após sql/ddl/bronze_tables.sql.
-- Substituir <BUCKET> pelo nome real do data lake antes de rodar.
--
-- PARTITIONED BY (day(ingested_at)) é particionamento oculto do Iceberg:
-- não existe mais year=/month=/day=/hour= como pastas manuais no S3.
-- O Iceberg gerencia isso no metadado da tabela — evolui sem precisar
-- de MSCK REPAIR nem de recriar a tabela se a granularidade mudar depois.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE silver.trades (
    trade_id        bigint,
    symbol          string,       -- ex: BTCUSDT (mantido como veio da Binance)
    asset_symbol    string,       -- ex: BTC (normalizado, usado no join da gold)
    price           decimal(38,8),
    quantity        decimal(38,8),
    trade_time      timestamp,
    is_buyer_maker  boolean,
    ingested_at     timestamp
)
PARTITIONED BY (day(ingested_at))
LOCATION 's3://crypto-pipeline-datalake-396095212540/silver/trades/'
TBLPROPERTIES (
    'table_type' = 'ICEBERG',
    'format' = 'parquet'
);

CREATE TABLE silver.market_snapshot (
    id                                        string,
    symbol                                    string,       -- ex: btc (como vem da CoinGecko)
    asset_symbol                              string,       -- ex: BTC (normalizado, usado no join da gold)
    name                                      string,
    current_price                             decimal(38,8),
    market_cap                                decimal(38,8),
    market_cap_rank                           int,
    fully_diluted_valuation                   decimal(38,8),
    total_volume                              decimal(38,8),
    high_24h                                  decimal(38,8),
    low_24h                                   decimal(38,8),
    price_change_24h                          decimal(38,8),
    price_change_percentage_24h               decimal(18,8),
    market_cap_change_24h                     decimal(38,8),
    market_cap_change_percentage_24h          decimal(18,8),
    circulating_supply                        decimal(38,8),
    total_supply                              decimal(38,8),
    max_supply                                decimal(38,8),
    ath                                       decimal(38,8),
    ath_change_percentage                     decimal(18,8),
    ath_date                                  timestamp,
    atl                                       decimal(38,8),
    atl_change_percentage                     decimal(18,8),
    atl_date                                  timestamp,
    last_updated                              timestamp,
    price_change_percentage_1h_in_currency    decimal(18,8),
    price_change_percentage_24h_in_currency   decimal(18,8),
    price_change_percentage_7d_in_currency    decimal(18,8),
    ingested_at                               timestamp
)
PARTITIONED BY (day(ingested_at))
LOCATION 's3://crypto-pipeline-datalake-396095212540/silver/market_snapshot/'
TBLPROPERTIES (
    'table_type' = 'ICEBERG',
    'format' = 'parquet'
);
