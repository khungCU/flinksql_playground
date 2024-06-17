# Docker compose file old
The Docker Compose environment consists of the following containers:

Flink SQL CLI: used to submit queries and visualize their results.
Flink Cluster: a Flink JobManager and a Flink TaskManager container to execute queries.
MySQL: MySQL 5.7 and a pre-populated category table in the database. The category table will be joined with data in Kafka to enrich the real-time data.
Kafka: mainly used as a data source. The DataGen component automatically writes data into a Kafka topic.
Zookeeper: this component is required by Kafka.
Elasticsearch: mainly used as a data sink.
Kibana: used to visualize the data in Elasticsearch
DataGen: the data generator. After the container is started, user behavior data is automatically generated and sent to the Kafka topic. By default, 2000 data entries are generated each second for about 1.5 hours. You can modify DataGen’s speedup parameter in docker-compose.yml to adjust the generation rate (which takes effect after Docker Compose is restarted).



# Docker compose file
redpanda-1 is the name of the Redpanda broker that your Flink application will interact with.
jobmanager is the Flink job manager, which will coordinate execution of your stream processing applications.
taskmanager is the Flink task manager, which will actually execute your Flink queries.
sql-client is the Flink SQL client, where you'll write queries and submit your jobs to the job manager.


----------- Hands on

use rpk in this tutorial, set the following alias so that any invocation of the rpk command invokes the pre-installed version inside the broker container.
	alias rpk="docker exec -ti redpanda-1 rpk"

-- red pandas kafka topic operation
rpk topic create names greetings purchases -p 4
rpk topic list
rpk topic delete purchases
rpk topic describe greetings
rpk topic create users \
    -c cleanup.policy=compact
rpk topic alter-config greetings \
    --set retention.ms=1209600000

-- Produce msg maual to the topic
rpk topic produce names

-- Consume msg from a topic
rpk topic consume names
rpk topic consume names --group my-group

-- Consumer group
rpk group list
rpk group seek my-group \
    --topics names \
    --to start

-- Consume topic at point in time 
# helper function to get a timestamp (epoch in ms) for x minutes ago
minago () {
    echo $(($(date +"%s000 - ($1 * 60000)")))
}

rpk group seek my-group \
    --topics names \
    --to $(minago 10)


### Workshop 1 Flink SQL Basic

-- create topic
alias rpk="docker-compose exec -T redpanda-1 rpk"
rpk topic create names greetings -p 4

-- write to the topic
json_records=(
    '{"name": "Flink", "website": "flink.apache.org"}'
    '{"name": "Redpanda", "website": "redpanda.com"}'
    '{"name": "Alpaca", "website": "alpaca.markets"}'
)

for json in "${json_records[@]}"; do
    echo $json | rpk topic produce names --allow-auto-topic-creation
done

-- Enter sql client interface
docker-compose run sql-client

-- Configure the flink sql output
- adjust the output format to improve readability
SET 'sql-client.execution.result-mode' = 'tableau';
- set the name of our Flink job
SET 'pipeline.name' = 'Hello, World';

-- Create a stream from kafka topic (source)
- https://nightlies.apache.org/flink/flink-docs-master/docs/dev/table/sql/create/#create-table

CREATE TABLE names (name VARCHAR, website VARCHAR) WITH (
    'connector' = 'kafka',
    'topic' = 'names',
    'properties.bootstrap.servers' = 'redpanda-1:29092',
    'properties.group.id' = 'test-group',
    'properties.auto.offset.reset' = 'earliest',
    'format' = 'json'
);

-- Explore the stream
SHOW TABLES ;
DESCRIBE names ;
SELECT * FROM names ;


-- Create a sink
CREATE TABLE greetings WITH (
    'connector' = 'kafka',
    'topic' = 'greetings',
    'properties.bootstrap.servers' = 'redpanda-1:29092',
    'format' = 'json'
) AS
SELECT
    CONCAT('Hello, ', name) as greeting,
    PROCTIME() as processing_time
FROM
    names;
# flinksql_playground
