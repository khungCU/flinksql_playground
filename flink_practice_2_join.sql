-- 01_regular_joins


-- 02_interval_joins


-- 03_kafka_join a.k.a temporal join(kafka-upsert join with kafka)
CREATE TEMPORARY TABLE currency_rates (
  `currency_code` STRING,
  `eur_rate` DECIMAL(6,4),
  `rate_time` TIMESTAMP(3),
  WATERMARK FOR `rate_time` AS rate_time - INTERVAL '15' SECOND,
  PRIMARY KEY (currency_code) NOT ENFORCED
) WITH (
  'connector' = 'upsert-kafka',
  'topic' = 'currency_rates',
  'properties.bootstrap.servers' = 'kafka:9093',
  'key.format' = 'raw',
  'value.format' = 'json'
);

CREATE TEMPORARY TABLE currency_rates_faker
WITH (
  'connector' = 'faker',
  'fields.currency_code.expression' = '#{Currency.code}',
  'fields.eur_rate.expression' = '#{Number.randomDouble ''4'',''0'',''10''}',
  'fields.rate_time.expression' = '#{date.past ''15'',''SECONDS''}', 
  'rows-per-second' = '100'
) LIKE currency_rates (EXCLUDING OPTIONS);

INSERT INTO currency_rates 
  SELECT * FROM currency_rates_faker;

CREATE TEMPORARY TABLE transactions (
  `id` STRING,
  `currency_code` STRING,
  `total` DECIMAL(10,2),
  `transaction_time` TIMESTAMP(3),
  WATERMARK FOR `transaction_time` AS transaction_time - INTERVAL '15' SECOND
) WITH (
  'connector' = 'kafka',
  'topic' = 'transactions',
  'properties.bootstrap.servers' = 'kafka:9093',
  'properties.group.id' = 'transcationsGroup',
  'scan.startup.mode' = 'earliest-offset',
  'key.format' = 'raw',
  'key.fields' = 'id',
  'value.format' = 'json',
  'value.fields-include' = 'ALL'
);

CREATE TEMPORARY TABLE transactions_faker
WITH (
  'connector' = 'faker',
  'fields.id.expression' = '#{Internet.UUID}',
  'fields.currency_code.expression' = '#{Currency.code}',
  'fields.total.expression' = '#{Number.randomDouble ''2'',''10'',''1000''}',
  'fields.transaction_time.expression' = '#{date.past ''5'',''SECONDS''}',
  'rows-per-second' = '100'
) LIKE transactions (EXCLUDING OPTIONS);

INSERT INTO transactions
  SELECT * FROM transactions_faker;

SELECT 
  t.id,
  t.total * c.eur_rate AS total_eur,
  t.total, 
  c.currency_code,
  t.transaction_time
FROM transactions t
JOIN currency_rates FOR SYSTEM_TIME AS OF t.transaction_time AS c
ON t.currency_code = c.currency_code;

-- 04_lookup_joins


-- 05_star_schema

-- 06_lateral_join


-- /opt/flink/bin/sql-client.sh -l lib/
