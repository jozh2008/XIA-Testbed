FROM ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git \
    gcc-7 g++-7 \
    libxml2 libxml2-dev \
    libssl-dev \
    libprotobuf-dev protobuf-compiler \
    python-protobuf python-networkx python-nacl \
    python-pip python-tk python-dev python-requests python-crypto \
    build-essential openssl swig \
    iproute2 iputils-ping net-tools tcpdump \
    rsyslog \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone https://github.com/XIA-Project/xia-core.git
WORKDIR /opt/xia-core
# xia-v2 is the branch the maintainers recommend for evaluators
RUN git checkout xia-v2

RUN ./configure && make

ENV PATH="/opt/xia-core/bin:${PATH}"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]