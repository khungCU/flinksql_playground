--Register the Python UDF using the fully qualified 
--name of the function ([module name].[object name])
CREATE FUNCTION to_fahr AS 'python_udf.to_fahr' 
LANGUAGE PYTHON;


CREATE TABLE temperature_measurements (
  city STRING,
  temperature FLOAT,
  measurement_time TIMESTAMP(3),
  WATERMARK FOR measurement_time AS measurement_time - INTERVAL '15' SECONDS
)
WITH (
  'connector' = 'faker',
  'fields.temperature.expression' = '#{number.numberBetween ''0'',''42''}',
  'fields.measurement_time.expression' = '#{date.past ''15'',''SECONDS''}',
  'fields.city.expression' = '#{regexify ''(Copenhagen|Berlin|Chicago|Portland|Seattle|New York){1}''}'
);


--Use to_fahr() to convert temperatures in US cities from C to F
SELECT city,
       temperature AS tmp,
       to_fahr(city,temperature) AS tmp_conv,
       measurement_time
FROM temperature_measurements;


-- /opt/flink/bin/sql-client.sh -pyclientexec /usr/bin/python -pyexec /usr/bin/python -pyfs /opt/sql-client/udf/python_udf.py -l lib/

-- SET 'python.files'='file:///opt/sql-client/udf/python_udf.py';
-- SET 'python.executable'='/usr/bin/';
-- SET 'python.client.executable'='/usr/bin/';