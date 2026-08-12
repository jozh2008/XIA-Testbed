#!/bin/bash
# Startup script for XIA host nodes (non-router, non-nameserver).

cd /opt/xia-core

rsyslogd

rm -f /tmp/xsocket* /tmp/icid* /tmp/xcache* /tmp/click*
./bin/xianet kill || true

# Host nodes need a copy of the nameserver's resolv.conf before they can start.
echo "[$(hostname)] waiting for router resolv.conf..."
until [ -f /shared/resolv.conf ]; do
    sleep 1
done
cp /shared/resolv.conf etc/resolv.conf

echo "[$(hostname)] starting XIA host..."
./bin/xianet -t start || true

# Publish our own MAC address so the router can pin a STATIC ARP entry for
# us later (dynamic ARP entries were observed to only ever hold one host at
# a time on the router, evicting/overwriting whichever host wasn't most
# recently resolved -- static entries avoid that).
cat /sys/class/net/eth0/address > /shared/mac_$(hostname).txt

# Publish our own DAG line (used to build etc/hosts.xia for xping/xtraceroute).
until xdag > /shared/dag_$(hostname).txt 2>/dev/null && [ -s /shared/dag_$(hostname).txt ]; do
    sleep 1
done

# Wait until every HOST node in the topology has published its DAG line
# (the router deliberately does not participate -- xdag/hosts.xia is only
# meaningful for hosts, which is what xping/xtraceroute target), then
# assemble the combined etc/hosts.xia locally.
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