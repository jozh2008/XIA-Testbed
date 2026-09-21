#!/bin/bash

# Startup script for XIA host nodes.
#
# Environment:
#
#   XIA_PEER_HOSTS
#       Space-separated list of hostnames whose DAGs must be present
#       before this node builds hosts.xia.
#
#       Example:
#           XIA_PEER_HOSTS="host0"
#           XIA_PEER_HOSTS="server0 server1"
#
#       If unset, this node waits only for itself.

cd /opt/xia-core

rsyslogd

rm -f /tmp/xsocket* /tmp/icid* /tmp/xcache* /tmp/click*
./bin/xianet kill || true

# ----------------------------------------------------------------------
# Wait for the nameserver router to publish the CURRENT resolver config.
# ----------------------------------------------------------------------


echo "[$(hostname)] waiting for router nameserver..."

until [ -f /shared/nameserver.ready ]; do
    sleep 1
done

cp /shared/resolv.conf etc/resolv.conf

echo "[$(hostname)] using nameserver:"
cat etc/resolv.conf

# ----------------------------------------------------------------------
# Start XIA host.
# ----------------------------------------------------------------------


echo "[$(hostname)] starting XIA host..."
./bin/xianet -t start || true

# ----------------------------------------------------------------------
# Publish this host's MAC address.
# The router can use this to pin a static ARP entry.
# ----------------------------------------------------------------------


cat /sys/class/net/eth0/address > /shared/mac_$(hostname).txt

# ----------------------------------------------------------------------
# Publish this host's DAG.
# ----------------------------------------------------------------------


until xdag > /shared/dag_$(hostname).txt 2>/dev/null && [ -s /shared/dag_$(hostname).txt ]; do
    sleep 1
done

# ----------------------------------------------------------------------
# Determine which peer hosts we need to wait for.
#
# If XIA_PEER_HOSTS is unset, default to this host only so that a node
# never blocks forever waiting for hosts that were never configured.
# ----------------------------------------------------------------------

if [ -n "$XIA_PEER_HOSTS" ]; then
    PEER_HOSTS="$XIA_PEER_HOSTS"
else
    echo "[$(hostname)] WARNING: XIA_PEER_HOSTS not set, defaulting to self only"
    PEER_HOSTS="$(hostname)"
fi

echo "[$(hostname)] waiting for peer hosts: $PEER_HOSTS"

# Wait until every configured peer host has published its DAG line.
for host in $PEER_HOSTS; do
    until [ -s /shared/dag_${host}.txt ]; do
        sleep 1
    done
done

# ----------------------------------------------------------------------
# Build hosts.xia.
#
# At this point all configured peers are guaranteed to have published
# their DAGs. Include every currently published DAG, as in the original.
# ----------------------------------------------------------------------

cat /shared/dag_*.txt > etc/hosts.xia

echo "[$(hostname)] hosts.xia ready:"
cat etc/hosts.xia

./bin/xianet check || true

tail -f /dev/null