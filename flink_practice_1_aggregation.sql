-- 01 Aggregating Time Series Data
CREATE TABLE server_logs ( 
    client_ip STRING,
    client_identity STRING, 
    userid STRING, 
    request_line STRING, 
    status_code STRING, 
    log_time AS PROCTIME()
) WITH (
  'connector' = 'faker', 
  'fields.client_ip.expression' = '#{Internet.publicIpV4Address}',
  'fields.client_identity.expression' =  '-',
  'fields.userid.expression' =  '-',
  'fields.log_time.expression' =  '#{date.past ''15'',''5'',''SECONDS''}',
  'fields.request_line.expression' = '#{regexify ''(GET|POST|PUT|PATCH){1}''} #{regexify ''(/search\.html|/login\.html|/prod\.html|cart\.html|/order\.html){1}''} #{regexify ''(HTTP/1\.1|HTTP/2|/HTTP/1\.0){1}''}',
  'fields.status_code.expression' = '#{regexify ''(200|201|204|400|401|403|301){1}''}'
);

SELECT 
    window_start, 
    window_end, 
    client_ip, 
    COUNT(status_code) AS status_code_count
FROM TABLE(TUMBLE(TABLE server_logs, DESCRIPTOR(log_time), INTERVAL '1' MINUTE))
GROUP BY window_start, window_end, client_ip;

-- 02 Watermarks
-- 
CREATE TABLE doctor_sightings (
  doctor        STRING,
  sighting_time TIMESTAMP(3),
  WATERMARK FOR sighting_time AS sighting_time - INTERVAL '15' SECONDS
)
WITH (
  'connector' = 'faker', 
  'fields.doctor.expression' = '#{dr_who.the_doctors}',
  'fields.sighting_time.expression' = '#{date.past ''15'',''SECONDS''}'
);

SELECT 
    window_start, 
    window_end,
    window_time,
    doctor,
    COUNT(*) AS sightings
FROM TABLE(TUMBLE(TABLE doctor_sightings, DESCRIPTOR(sighting_time), INTERVAL '1' MINUTE))
GROUP BY 
    window_start,
    window_end,
    window_time,
    doctor;

-- 04 Rolling Aggregations on Time Series Data
CREATE TEMPORARY TABLE temperature_measurements (
  measurement_time TIMESTAMP(3),
  city STRING,
  temperature FLOAT, 
  WATERMARK FOR measurement_time AS measurement_time - INTERVAL '15' SECONDS
)
WITH (
  'connector' = 'faker',
  'fields.measurement_time.expression' = '#{date.past ''30'',''SECONDS''}',
  'fields.temperature.expression' = '#{number.numberBetween ''0'',''50''}',
  'fields.city.expression' = '#{regexify ''(Chicago|Munich|Berlin|Portland|Hangzhou|Seatle|Beijing|New York){1}''}'
);

-- To identify outliers in the temperature_measurements table.
/* To calculate, for each measurement, the maximum (MAX), 
                                           minimum (MIN) 
                                       and average (AVG) 
  temperature across all measurements, as well as the standard deviation (STDDEV), for the same city over the previous minute.
*/
SELECT 
  measurement_time,
  city, 
  temperature,
  AVG(CAST(temperature AS FLOAT)) OVER last_minute AS avg_temperature_minute,
  MIN(temperature) OVER last_minute AS min_temperature_minute,
  MAX(temperature) OVER last_minute AS max_temperature_minute,
  STDDEV(CAST(temperature AS FLOAT)) OVER last_minute AS stdev_temperature_minute
FROM temperature_measurements 
WINDOW last_minute AS (
  PARTITION BY city
  ORDER BY measurement_time
  RANGE BETWEEN INTERVAL '1' MINUTE PRECEDING AND CURRENT ROW 
);

-- 05 Continuous Top-N
CREATE TABLE spells_cast (
    wizard STRING,
    spell  STRING
) WITH (
  'connector' = 'faker',
  'fields.wizard.expression' = '#{harry_potter.characters}',
  'fields.spell.expression' = '#{harry_potter.spells}'
);

-- To find each wizard's top 2 favorite spells
WITH spell_count AS (
    SELECT wizard, 
           spell, 
           COUNT(*) AS times_cast 
    FROM spells_cast 
    GROUP BY wizard, spell
)
SELECT 
   wizard, 
   spell, 
   times_cast
FROM (
    SELECT 
         wizard, spell, times_cast,
         ROW_NUMBER() OVER (PARTITION BY wizard ORDER BY times_cast DESC) AS row_num
    FROM spell_count) 
WHERE row_num <= 2;


-- 06 dedup
CREATE TABLE orders (
  id INT,
  order_time AS CURRENT_TIMESTAMP,
  WATERMARK FOR order_time AS order_time - INTERVAL '5' SECONDS
)
WITH (
  'connector' = 'datagen',
  'rows-per-second'='10',
  'fields.id.kind'='random',
  'fields.id.min'='1',
  'fields.id.max'='100'
);

SELECT 
  order_id,
  order_time,
  rownum
FROM (
  SELECT 
    id AS order_id,
    order_time,
    row_number() OVER (PARTITION BY id ORDER BY order_time) AS rownum
  FROM orders)
WHERE rownum = 1;

-- 07 Chained (Event) Time Windows (SINK to multiple tables)
CREATE TEMPORARY TABLE server_logs ( 
    log_time TIMESTAMP(3),
    client_ip STRING,
    client_identity STRING, 
    userid STRING, 
    request_line STRING, 
    status_code STRING, 
    size INT, 
    WATERMARK FOR log_time AS log_time - INTERVAL '15' SECONDS
) WITH (
  'connector' = 'faker', 
  'fields.log_time.expression' =  '#{date.past ''15'',''5'',''SECONDS''}',
  'fields.client_ip.expression' = '#{Internet.publicIpV4Address}',
  'fields.client_identity.expression' =  '-',
  'fields.userid.expression' =  '-',
  'fields.request_line.expression' = '#{regexify ''(GET|POST|PUT|PATCH){1}''} #{regexify ''(/search\.html|/login\.html|/prod\.html|cart\.html|/order\.html){1}''} #{regexify ''(HTTP/1\.1|HTTP/2|/HTTP/1\.0){1}''}',
  'fields.status_code.expression' = '#{regexify ''(200|201|204|400|401|403|301){1}''}',
  'fields.size.expression' = '#{number.numberBetween ''100'',''10000000''}'
);


CREATE TEMPORARY TABLE avg_request_size_1m (
  window_start TIMESTAMP(3),
  window_end TIMESTAMP(3),
  avg_size BIGINT
) WITH (
  'connector' = 'blackhole'
);

CREATE TEMPORARY TABLE avg_request_size_5m (
  window_start TIMESTAMP(3),
  window_end TIMESTAMP(3),
  avg_size BIGINT
) WITH (
  'connector' = 'blackhole'
);

SELECT
  window_start,
  window_end,
  SUM(size) AS total_size,
  COUNT(*) AS num_requests
FROM TABLE(TUMBLE(TABLE server_logs, DESCRIPTOR(log_time) , INTERVAL '1' MINUTE))
GROUP BY window_start, window_end;


-- 08 JDBC source connector
-- Every time Flink need to query the table
-- The result is static after a select query 
CREATE TABLE accident_claims_jdbc (
    claim_id INT,
    claim_total DOUBLE,
    claim_total_receipt VARCHAR(50),
    claim_currency VARCHAR(3),
    member_id INT,
    accident_date VARCHAR(20),
    accident_type VARCHAR(20),
    accident_detail VARCHAR(20),
    claim_date VARCHAR(20),
    claim_status VARCHAR(10),
    ts_created VARCHAR(20),
    ts_updated VARCHAR(20)
) WITH (
  'connector' = 'jdbc',
  'url' = 'jdbc:postgresql://postgres:5432/postgres',
  'table-name' = 'claims.accident_claims',
  'username' = 'postgres',
  'password' = 'postgres'
 );

-- 09 CDC materialized view
-- Think as a snapshot in Flink
CREATE TABLE accident_claims_cdc (
    claim_id INT,
    claim_total DOUBLE,
    claim_total_receipt VARCHAR(50),
    claim_currency VARCHAR(3),
    member_id INT,
    accident_date VARCHAR(20),
    accident_type VARCHAR(20),
    accident_detail VARCHAR(20),
    claim_date VARCHAR(20),
    claim_status VARCHAR(10),
    ts_created VARCHAR(20),
    ts_updated VARCHAR(20)
) WITH (
  'connector' = 'postgres-cdc',
  'hostname' = 'postgres',
  'slot.name' = 'test_slot',
  'port' = '5432',
  'username' = 'postgres',
  'password' = 'postgres',
  'database-name' = 'postgres',
  'schema-name' = 'claims',
  'table-name' = 'accident_claims'
 );

-- 12 Retrieve previous row value without self-join
CREATE TABLE fake_stocks ( 
    stock_name STRING,
    stock_value double, 
    log_time AS PROCTIME()
) WITH (
  'connector' = 'faker', 
  'fields.stock_name.expression' = '#{regexify ''(Deja\ Brew|Jurassic\ Pork|Lawn\ \&\ Order|Pita\ Pan|Bread\ Pitt|Indiana\ Jeans|Thai\ Tanic){1}''}',
  'fields.stock_value.expression' =  '#{number.randomDouble ''2'',''10'',''20''}',
  'fields.log_time.expression' =  '#{date.past ''15'',''5'',''SECONDS''}',
  'rows-per-second' = '10'
);

WITH current_and_previous AS (
  SELECT
    stock_name,
    stock_value,
    LAG(stock_value, 1) OVER (PARTITION BY stock_name ORDER BY log_time) AS previous_value
  FROM fake_stocks
)
SELECT *,
  case 
        when stock_value > previous_value then '▲'
        when stock_value < previous_value then '▼'
        else '=' 
  end as trend 
FROM current_and_previous;

