FROM ubuntu:18.04

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies, network utilities, and Python 2/3 requirements for XIA
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    cmake \
    libssl-dev \
    libprotobuf-dev \
    protobuf-compiler \
    libxml2-dev \
    iproute2 \
    net-tools \
    iputils-ping \
    python3 \
    python3-dev \
    python3-pip \
    python-dev \
    python-pip \
    python-protobuf \
    python-networkx \
    rsyslog \
    libffi-dev \
    swig \
    sudo \
    && rm -rf /var/lib/apt-get/lists/*

# Install PyNaCl for Python 2 (required by xnetjd)
RUN pip2 install pynacl

# Clone into a clean location and build sequentially
WORKDIR /opt
# RUN git clone -b xia-v2 https://github.com/XIA-Project/xia-core.git /opt/xia-core
RUN git clone https://github.com/XIA-Project/xia-core.git /opt/xia-core
WORKDIR /opt/xia-core
RUN ./configure && make

# Bake in the container startup scripts used by docker-compose
COPY scripts/start-router.sh /opt/xia-core/scripts/start-router.sh
COPY scripts/start-node.sh /opt/xia-core/scripts/start-node.sh
RUN chmod +x /opt/xia-core/scripts/start-router.sh /opt/xia-core/scripts/start-node.sh

# Set environment variables
ENV XIA_HOME=/opt/xia-core
ENV PATH=$PATH:/opt/xia-core/bin:/opt/xia-core/sbin

CMD ["/bin/bash"]