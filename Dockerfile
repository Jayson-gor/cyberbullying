FROM ubuntu:22.04

# Update apt sources and install base dependencies
RUN sed -i -e "s|http://archive.ubuntu.com|http://jp.archive.ubuntu.com|g" /etc/apt/sources.list \
 && apt-get -qq update \
 && DEBIAN_FRONTEND=noninteractive apt-get -qq install --no-install-recommends \
      sudo \
      openjdk-8-jdk \
      curl \
      gnupg \
      procps \
      python3 \
      python3-pip \
      python-is-python3 \
      coreutils \
      libc6-dev \
      vim \
      openssh-server \
      openssh-client \
      netcat \
      nodejs \
 && rm -rf /var/lib/apt/lists/*

# Create jupyter user
ARG USERNAME=jupyter
ARG GROUPNAME=jupyter
ARG UID=1001
ARG GID=1001

RUN echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
 && chmod 0440 /etc/sudoers.d/$USERNAME \
 && groupadd -g $GID $GROUPNAME \
 && useradd -m -s /bin/bash -u $UID -g $GID $USERNAME

USER $USERNAME
WORKDIR /home/jupyter

# Set environment variables
ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
ENV SPARK_HOME=/opt/spark
ENV SPARK_CONF_DIR=$SPARK_HOME/conf
ENV PATH=$HADOOP_HOME/sbin:$HADOOP_HOME/bin:$SPARK_HOME/sbin:$SPARK_HOME/bin:/home/jupyter/.local/bin:$JAVA_HOME/bin:$PATH
ENV LD_LIBRARY_PATH=$HADOOP_HOME/lib/native
ENV PYTHONHASHSEED=1
ENV PYSPARK_PYTHON=python3

# Install Hadoop
ARG HADOOP_VERSION=3.3.6
ARG HADOOP_URL=https://www.apache.org/dist/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz

RUN set -x \
 && curl -fsSL https://archive.apache.org/dist/hadoop/common/KEYS -o /tmp/hadoop-KEYS \
 && gpg --import /tmp/hadoop-KEYS \
 && sudo mkdir $HADOOP_HOME \
 && sudo chown $USERNAME:$GROUPNAME -R $HADOOP_HOME \
 && curl -fsSL $HADOOP_URL -o /tmp/hadoop.tar.gz \
 && curl -fsSL $HADOOP_URL.asc -o /tmp/hadoop.tar.gz.asc \
 && gpg --verify /tmp/hadoop.tar.gz.asc \
 && tar -xf /tmp/hadoop.tar.gz -C $HADOOP_HOME --strip-components 1 \
 && mkdir $HADOOP_HOME/logs \
 && rm /tmp/hadoop*

# Install Spark
ARG SPARK_VERSION=3.5.3
ARG SPARK_URL=https://archive.apache.org/dist/spark/spark-$SPARK_VERSION/spark-$SPARK_VERSION-bin-hadoop3.tgz

RUN set -x \
 && curl -fsSL https://archive.apache.org/dist/spark/KEYS -o /tmp/spark-KEYS \
 && gpg --import /tmp/spark-KEYS \
 && sudo mkdir $SPARK_HOME \
 && sudo chown $USERNAME:$GROUPNAME -R $SPARK_HOME \
 && curl -fsSL $SPARK_URL -o /tmp/spark.tgz \
 && curl -fsSL $SPARK_URL.asc -o /tmp/spark.tgz.asc \
 && gpg --verify /tmp/spark.tgz.asc \
 && tar -xf /tmp/spark.tgz -C $SPARK_HOME --strip-components 1 \
 && rm /tmp/spark*

# Install Python libraries with fewer retries
RUN python3 -m pip install --upgrade pip --timeout 1000 \
 && pip install --timeout 1000 --retries 3 \
    pyspark==3.5.1 \
    spark-nlp==5.1.4 \
    jupyterlab \
    pandas \
    numpy \
    matplotlib \
    seaborn \
    scikit-learn \
    nltk \
    transformers \
    beautifulsoup4 \
    regex \
    tensorflow \
    keras \
    vaderSentiment \
    textblob \
    wordcloud \
    spacy \
    pyarrow \
    streamlit \
 && pip install --timeout 1000 --retries 3 --index-url https://download.pytorch.org/whl/cpu \
    torch

# Download NLTK data during build to a user-writable directory
RUN python3 -m nltk.downloader -d /home/jupyter/nltk_data wordnet omw-1.4 punkt stopwords vader_lexicon

# Pre-download spaCy data
RUN python3 -m spacy download en_core_web_sm

# Config files (including updated yarn-site.xml)
COPY --chown=$USERNAME:$GROUPNAME conf/core-site.xml $HADOOP_CONF_DIR/
COPY --chown=$USERNAME:$GROUPNAME conf/hdfs-site.xml $HADOOP_CONF_DIR/
COPY --chown=$USERNAME:$GROUPNAME conf/yarn-site.xml $HADOOP_CONF_DIR/
COPY --chown=$USERNAME:$GROUPNAME conf/mapred-site.xml $HADOOP_CONF_DIR/
COPY --chown=$USERNAME:$GROUPNAME conf/workers $HADOOP_CONF_DIR/
COPY --chown=$USERNAME:$GROUPNAME conf/spark-defaults.conf $SPARK_CONF_DIR/
COPY --chown=$USERNAME:$GROUPNAME conf/log4j.properties $SPARK_CONF_DIR/

RUN ln -s $HADOOP_CONF_DIR/workers $SPARK_CONF_DIR/

# Project files
COPY --chown=$USERNAME:$GROUPNAME data /app/data
COPY --chown=$USERNAME:$GROUPNAME scripts /app/scripts
COPY --chown=$USERNAME:$GROUPNAME report /app/report

# Expose ports for HDFS, YARN, JupyterLab, and Streamlit
EXPOSE 8080 8088 9000 8888 8501

# Entry point
COPY --chown=$USERNAME:$GROUPNAME entrypoint.sh /usr/local/sbin/entrypoint.sh
RUN chmod a+x /usr/local/sbin/entrypoint.sh
ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]

# Volumes
VOLUME /opt/hadoop/dfs/name
VOLUME /opt/hadoop/dfs/data