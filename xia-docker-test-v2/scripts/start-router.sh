#!/bin/bash
# Startup script for the XIA router/nameserver node.

cd /opt/xia-core

rsyslogd

rm -f /tmp/xsocket* /tmp/icid* /tmp/xcache* /tmp/click*
./bin/xianet kill || true

echo "[$(hostname)] starting XIA router + nameserver..."
./bin/xianet -r -n start || true

# Wait for xianet to generate resolv.conf, then publish it on the shared
# volume so the host nodes (which are not routers/nameservers) can pick it up.
mkdir -p /shared
until [ -f etc/resolv.conf ]; do
    sleep 1
done
cp etc/resolv.conf /shared/resolv.conf
echo "[$(hostname)] published resolv.conf"

# NOTE: xdag / hosts.xia are only meaningful for host nodes (xping/xtraceroute
# target hosts, not routers), so the router does not publish or wait for a
# DAG entry of its own -- see the wiki's Running-XIA example, which only runs
# xdag on Host0/Server0/Server1, never on the routers.
#
# Still build a local hosts.xia from whatever host nodes are in the topology,
# purely so the router can also `xping` a host by name if useful.
for n in xia-node1 xia-node2; do
    until [ -s /shared/dag_$n.txt ]; do
        sleep 1
    done
done
cat /shared/dag_xia-node*.txt > etc/hosts.xia
echo "[$(hostname)] hosts.xia ready:"
cat etc/hosts.xia

# NOTE: static ARP pinning via `xarp -a ... static` was tried here and
# rejected by Click at the protocol level ("error 520: STATIC: parse
# error"), regardless of HID formatting -- it appears unsupported/broken
# in this build, so it has been removed rather than risk leaving Click's
# ARP table handler in a bad state.

./bin/xianet check || true

tail -f /dev/null