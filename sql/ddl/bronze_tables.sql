-- ══════════════════════════════════════════════════════════════════
-- crypto-pipeline — DDL do bronze (external tables sobre JSON cru)
-- Rodar MANUALMENTE, uma vez, após o terraform apply de infra/athena/.
-- As databases (bronze/silver/gold) já existem — criadas pelo Terraform.
-- Substituir <BUCKET> pelo nome real do data lake antes de rodar.
--
-- projection.enabled substitui o Crawler/MSCK REPAIR: o Athena calcula
-- as partições existentes na hora da query, a partir do padrão de path,
-- em vez de precisar de uma chamada explícita toda vez que uma nova
-- partição (hora) é criada.
-- ══════════════════════════════════════════════════════════════════

CREATE EXTERNAL TABLE bronze.trades (
    trade_id        bigint,
    symbol          string,
    price           string,
    quantity        string,
    trade_time      bigint,   -- epoch millis
    is_buyer_maker  boolean,
    ingested_at     string,   -- campo atual (pós-correção do nome no handler)
    _ingested_at    string    -- legado: arquivos gravados antes da correção do nome
)
PARTITIONED BY (year string, month string, day string, hour string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://crypto-pipeline-datalake-396095212540/bronze/trades/'
TBLPROPERTIES (
    'projection.enabled' = 'true',
    'projection.year.type' = 'integer',
    'projection.year.range' = '2026,2030',
    'projection.month.type' = 'integer',
    'projection.month.range' = '1,12',
    'projection.month.digits' = '2',
    'projection.day.type' = 'integer',
    'projection.day.range' = '1,31',
    'projection.day.digits' = '2',
    'projection.hour.type' = 'integer',
    'projection.hour.range' = '0,23',
    'projection.hour.digits' = '2',
    'storage.location.template' = 's3://crypto-pipeline-datalake-396095212540/bronze/trades/year=${year}/month=${month}/day=${day}/hour=${hour}/'
);

CREATE EXTERNAL TABLE bronze.coingecko (
    id                                       string,
    symbol                                   string,
    name                                     string,
    current_price                            double,
    market_cap                               double,
    market_cap_rank                          int,
    fully_diluted_valuation                  double,
    total_volume                             double,
    high_24h                                 double,
    low_24h                                  double,
    price_change_24h                         double,
    price_change_percentage_24h              double,
    market_cap_change_24h                    double,
    market_cap_change_percentage_24h         double,
    circulating_supply                       double,
    total_supply                             double,
    max_supply                               double,
    ath                                      double,
    ath_change_percentage                    double,
    ath_date                                 string,
    atl                                      double,
    atl_change_percentage                    double,
    atl_date                                 string,
    last_updated                             string,
    price_change_percentage_1h_in_currency   double,
    price_change_percentage_24h_in_currency  double,
    price_change_percentage_7d_in_currency   double,
    ingested_at                              string,  -- campo atual (pós-correção do nome no handler)
    _ingested_at                             string   -- legado: arquivos gravados antes da correção do nome
    -- roi e image propositalmente omitidos: JsonSerDe ignora chaves não
    -- declaradas aqui, então não precisam existir no schema.
)
PARTITIONED BY (year string, month string, day string, hour string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://crypto-pipeline-datalake-396095212540/bronze/coingecko/'
TBLPROPERTIES (
    'projection.enabled' = 'true',
    'projection.year.type' = 'integer',
    'projection.year.range' = '2026,2030',
    'projection.month.type' = 'integer',
    'projection.month.range' = '1,12',
    'projection.month.digits' = '2',
    'projection.day.type' = 'integer',
    'projection.day.range' = '1,31',
    'projection.day.digits' = '2',
    'projection.hour.type' = 'integer',
    'projection.hour.range' = '0,23',
    'projection.hour.digits' = '2',
    'storage.location.template' = 's3://crypto-pipeline-datalake-396095212540/bronze/coingecko/year=${year}/month=${month}/day=${day}/hour=${hour}/'
);
