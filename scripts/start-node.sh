#!/bin/bash

# Startup script for XIA host nodes (non-router, non-nameserver).
#
# Generalized: the set of peer hosts to wait for (for building hosts.xia)
# is no longer hardcoded to "xia-node1 xia-node2". Instead it's read from
# the XIA_PEER_HOSTS environment variable, a space-separated list of
# hostnames, e.g.:
#
#   environment:
#     - XIA_PEER_HOSTS=host0
#
# For a node with no peers on its local AD (e.g. an only-child host), set
# XIA_PEER_HOSTS to just its own hostname, or leave it unset -- see the
# fallback below.

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

# Determine the peer host list.
#   1. Use XIA_PEER_HOSTS if set (space-separated hostnames).
#   2. Otherwise fall back to just this node's own hostname, so a node
#      never blocks forever waiting for peers nobody configured.
if [ -n "$XIA_PEER_HOSTS" ]; then
    PEER_HOSTS="$XIA_PEER_HOSTS"
else
    echo "[$(hostname)] WARNING: XIA_PEER_HOSTS not set, defaulting to self only"
    PEER_HOSTS="$(hostname)"
fi

echo "[$(hostname)] waiting for peer hosts: $PEER_HOSTS"

# Wait until every configured peer host has published its DAG line.
for n in $PEER_HOSTS; do
    until [ -s /shared/dag_$n.txt ]; do
        sleep 1
    done
done

#cat $(for n in $PEER_HOSTS; do echo /shared/dag_$n.txt; done) > etc/hosts.xia
# Automatically bundle every DAG on the network into hosts.xia
cat /shared/dag_*.txt > etc/hosts.xia

echo "[$(hostname)] hosts.xia ready:"
cat etc/hosts.xia

./bin/xianet check || true

tail -f /dev/null