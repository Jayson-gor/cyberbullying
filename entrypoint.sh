#!/bin/bash

# Set NLTK data path
export NLTK_DATA=/home/jupyter/nltk_data

# Function to wait for a service to become available
function wait_for_it() {
    local serviceport=$1
    local service=${serviceport%%:*}
    local port=${serviceport#*:}
    local retry_seconds=5
    local max_try=100
    let i=1

    nc -z $service $port
    result=$?

    until [ $result -eq 0 ]; do
        echo "[$i/$max_try] Waiting for ${service}:${port}..."
        if (( $i == $max_try )); then
            echo "[$i/$max_try] ${service}:${port} still not available; giving up after ${max_try} tries."
            exit 1
        fi
        echo "[$i/$max_try] Retrying in ${retry_seconds}s..."
        let "i++"
        sleep $retry_seconds
        nc -z $service $port
        result=$?
    done
    echo "[$i/$max_try] ${service}:${port} is available."
}

# **Set NLTK data path**
export NLTK_DATA=/usr/local/share/nltk_data

# Start SSH service
sudo service ssh start

# Configure SSH for passwordless access
ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 0600 ~/.ssh/authorized_keys
echo "StrictHostKeyChecking no" >> ~/.ssh/config

# Initialize HDFS directories
sudo mkdir -p /opt/hadoop/dfs/name /opt/hadoop/dfs/data
sudo chown -R jupyter:jupyter /opt/hadoop/dfs

# Set JAVA_HOME and PATH
echo "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64" | sudo tee -a /etc/environment
echo "export PATH=$JAVA_HOME/bin:$PATH" | sudo tee -a /etc/environment
source /etc/environment

# Format HDFS if not already formatted
if [ ! -d "/opt/hadoop/dfs/name/current" ]; then
    $HADOOP_HOME/bin/hdfs namenode -format
fi

# Start HDFS and wait
$HADOOP_HOME/sbin/start-dfs.sh
wait_for_it localhost:9000

# Start YARN and wait
export YARN_CONF_DIR=$HADOOP_HOME/etc/hadoop
export YARN_RESOURCEMANAGER_HOSTNAME=0.0.0.0
$HADOOP_HOME/sbin/start-yarn.sh
wait_for_it localhost:8088

# Define the list of all datasets
datasets=(
    "aggression_parsed_dataset.csv"
    "attack_parsed_dataset.csv"
    "toxicity_parsed_dataset.csv"
    "twitter_parsed_dataset.csv"
    "twitter_racism_parsed_dataset.csv"
    "twitter_sexism_parsed_dataset.csv"
    "youtube_parsed_dataset.csv"
    "kaggle_parsed_dataset.csv"
    "hate_speech_dataset.csv"
    "additional_targeted_data.csv"
)

# Copy Spark jars and all datasets to HDFS
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /spark/jars
if [ -d "$SPARK_HOME/jars" ]; then
    $HADOOP_HOME/bin/hdfs dfs -put $SPARK_HOME/jars/* /spark/jars/
fi
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /input
for dataset in "${datasets[@]}"; do
    if [ -f "/app/data/$dataset" ]; then
        $HADOOP_HOME/bin/hdfs dfs -put /app/data/$dataset /input/
    else
        echo "Warning: /app/data/$dataset does not exist."
    fi
done

# Configure Spark settings
export SPARK_CONF_DIR=$SPARK_HOME/conf
> $SPARK_CONF_DIR/spark-defaults.conf  # Clear the file
echo "spark.sql.shuffle.partitions 10" >> $SPARK_CONF_DIR/spark-defaults.conf
echo "spark.ui.port 4040" >> $SPARK_CONF_DIR/spark-defaults.conf
echo "spark.driver.host 0.0.0.0" >> $SPARK_CONF_DIR/spark-defaults.conf
echo "spark.driver.bindAddress 0.0.0.0" >> $SPARK_CONF_DIR/spark-defaults.conf
echo "spark.yarn.jars hdfs://localhost:9000/spark/jars/*" >> $SPARK_CONF_DIR/spark-defaults.conf
# **Adjusted memory settings to fit within YARN's 12GB limit**
echo "spark.driver.memory 4g" >> $SPARK_CONF_DIR/spark-defaults.conf
echo "spark.executor.memory 4g" >> $SPARK_CONF_DIR/spark-defaults.conf
echo "spark.yarn.executor.memoryOverhead 1024" >> $SPARK_CONF_DIR/spark-defaults.conf
echo "spark.yarn.driver.memoryOverhead 1024" >> $SPARK_CONF_DIR/spark-defaults.conf

# Start Streamlit in the background
streamlit run /app/scripts/streamlit_app.py --server.port 8501 &

# Start JupyterLab
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.allow_origin='*'