#!/bin/bash

# Startup script for XIA host nodes (non-router, non-nameserver).

cd /opt/xia-core

rsyslogd

rm -f /tmp/xsocket* /tmp/icid* /tmp/xcache* /tmp/click*
./bin/xianet kill || true

# Host nodes wait for the router to publish the CURRENT nameserver
# configuration. The readiness marker prevents copying a stale
# resolv.conf left in the persistent shared Docker volume.

echo "[$(hostname)] waiting for router nameserver..."

until [ -f /shared/nameserver.ready ]; do
    sleep 1
done

cp /shared/resolv.conf etc/resolv.conf

echo "[$(hostname)] using nameserver:"
cat etc/resolv.conf

echo "[$(hostname)] starting XIA host..."
./bin/xianet -t start || true

# Publish our own MAC address so the router can pin a STATIC ARP entry for
# us later.

cat /sys/class/net/eth0/address > /shared/mac_$(hostname).txt

# Publish our own DAG line.

until xdag > /shared/dag_$(hostname).txt 2>/dev/null && [ -s /shared/dag_$(hostname).txt ]; do
    sleep 1
done

# Wait until every HOST node has published its DAG line.

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