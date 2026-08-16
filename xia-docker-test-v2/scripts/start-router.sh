#!/bin/bash

# Startup script for the XIA router/nameserver node.

cd /opt/xia-core

rsyslogd

rm -f /tmp/xsocket* /tmp/icid* /tmp/xcache* /tmp/click*
./bin/xianet kill || true

# Remove resolver state from a previous Docker run.
# The xia-shared volume survives container recreation.
rm -f /shared/resolv.conf
rm -f /shared/nameserver.ready

echo "[$(hostname)] starting XIA router + nameserver..."
./bin/xianet -r -n start || true

# Wait for xianet to generate the CURRENT resolv.conf, then publish it
# on the shared volume so host nodes can pick it up.

mkdir -p /shared

until [ -f etc/resolv.conf ]; do
    sleep 1
done

cp etc/resolv.conf /shared/resolv.conf

# Only signal readiness AFTER the complete current resolver has
# been published.
touch /shared/nameserver.ready

echo "[$(hostname)] published current resolv.conf:"
cat /shared/resolv.conf

# NOTE: xdag / hosts.xia are only meaningful for host nodes (xping/xtraceroute
# target hosts, not routers), so the router does not publish or wait for a
# DAG entry of its own.

# Still build a local hosts.xia from the host nodes in the topology.

for n in xia-node1 xia-node2; do
    until [ -s /shared/dag_$n.txt ]; do
        sleep 1
    done
done

cat /shared/dag_xia-node*.txt > etc/hosts.xia

echo "[$(hostname)] hosts.xia ready:"
cat etc/hosts.xia

./bin/xianet check || true

tail -f /dev/null