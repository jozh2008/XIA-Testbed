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
rm -f /shared/dag_xia-node*.txt

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

# xianet initially installs the router HID as a local route. During host
# network join that entry can be replaced with a route through port 0 whose
# next hop is the router HID itself. Restore the local route after both hosts
# have published their current DAGs so nameserver traffic does not loop until
# its hop limit expires.
router_hid=$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^HID:/) { print $i; exit } }' etc/resolv.conf)

if [ -z "$router_hid" ]; then
    echo "[$(hostname)] unable to read router HID from etc/resolv.conf" >&2
    exit 1
fi

./bin/xroute -a "HID,${router_hid},-2"
echo "[$(hostname)] restored router self-route for $router_hid"

cat /shared/dag_xia-node*.txt > etc/hosts.xia

echo "[$(hostname)] hosts.xia ready:"
cat etc/hosts.xia

./bin/xianet check || true

tail -f /dev/null
