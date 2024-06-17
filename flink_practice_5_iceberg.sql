/* Run the client with all the packages */
-- /opt/flink/bin/sql-client.sh -l lib/

/* Create the Catalog */
DROP CATALOG IF EXISTS nessie_catalog;
CREATE CATALOG nessie_catalog WITH (
'type'='iceberg', 
'catalog-impl'='org.apache.iceberg.nessie.NessieCatalog', 
'io-impl'='org.apache.iceberg.aws.s3.S3FileIO',
'uri'='http://catalog:19120/api/v1', 
'authentication.type'='none',
'client.assume-role.region'='us-east-1',
'warehouse'='s3://warehouse', 
's3.endpoint'='http://172.24.0.5:9000');
-- docker container inspect container_name_or_ID

show catalogs;
/*
output:
+-----------------+
|    catalog name |
+-----------------+
| default_catalog |
|  nessie_catalog |
+-----------------+
*/
USE CATALOG nessie_catalog;

/* Create database */
CREATE database db;
USE db;

/* Create table and insert table */
CREATE TABLE spotify (songid BIGINT, artist STRING, rating BIGINT);
INSERT INTO spotify VALUES (2, 'drake', 3);


/* upsert table */
DROP TABLE IF EXISTS spotify;
CREATE TABLE spotify (
  `songid`  INT UNIQUE,
  `artist` STRING NOT NULL,
  `ratings` INT,
 PRIMARY KEY(`songid`) NOT ENFORCED
) WITH ('format-version'='2', 'write.upsert.enabled'='true');

--  hint to upsert
-- hint syntax https://nightlies.apache.org/flink/flink-docs-release-1.17/docs/dev/table/sql/queries/hints/
INSERT INTO spotify /*+ OPTIONS('upsert-enabled'='true') */ VALUES (2, 'Rihanna', 4);


/* Read */
select * from spotify;


/* Review Metadata */
SELECT * FROM spotify$history;
SELECT * FROM spotify$metadata_log_entries;
SELECT * FROM spotify$snapshots;