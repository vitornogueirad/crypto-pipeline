-- ══════════════════════════════════════════════════════════════════
-- crypto-pipeline — DDL da gold (tabela Iceberg)
-- Rodar MANUALMENTE, uma vez, após sql/ddl/silver_tables.sql.
-- Substituir <BUCKET> pelo nome real do data lake antes de rodar.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE gold.anomalias (
    asset_symbol     string,
    janela_inicio    timestamp,
    janela_fim       timestamp,
    preco_vwap       decimal(38,8),
    volume_total     decimal(38,8),
    qtd_trades       bigint,
    baseline_media   decimal(38,8),
    baseline_desvio  decimal(38,8),
    z_score          decimal(18,8),
    anomalia         boolean
)
PARTITIONED BY (day(janela_inicio))
LOCATION 's3://crypto-pipeline-datalake-396095212540/gold/anomalias/'
TBLPROPERTIES (
    'table_type' = 'ICEBERG',
    'format' = 'parquet'
);
