#!/bin/bash

# Startup script for XIA router nodes.
#
# Environment:
#
#   XIA_NAMESERVER
#       "1" -> this router runs the nameserver.
#       anything else/unset -> plain router.
#
#   XIA_PEER_HOSTS
#       Space-separated list of hosts directly attached to this router.
#       Example:
#           router0 -> "host0"
#           router2 -> "server0 server1"
#       Empty/unset -> transit router with no local hosts.
#


cd /opt/xia-core

rsyslogd

rm -f /tmp/xsocket* /tmp/icid* /tmp/xcache* /tmp/click*
./bin/xianet kill || true

mkdir -p /shared

# ----------------------------------------------------------------------
# Remove stale DAG files belonging to hosts attached to THIS router.
# ----------------------------------------------------------------------

if [ -n "$XIA_PEER_HOSTS" ]; then
    for host in $XIA_PEER_HOSTS; do
        rm -f /shared/dag_${host}.txt
    done
fi

if [ "$XIA_NAMESERVER" = "1" ]; then
    # ------------------------------------------------------------------
    # Nameserver router
    # ------------------------------------------------------------------


     # The shared volume survives container recreation, so remove resolver
    # state from the previous run.
    rm -f /shared/resolv.conf
    rm -f /shared/nameserver.ready

    echo "[$(hostname)] starting XIA router + nameserver..."
    ./bin/xianet -r -n start || true

    # Wait for xianet to generate the CURRENT resolv.conf, then publish it
    # on the shared volume so other routers and host nodes can pick it up.
    until [ -f etc/resolv.conf ]; do
        sleep 1
    done

    cp etc/resolv.conf /shared/resolv.conf

    # Only signal readiness AFTER the complete current resolver has
    # been published.
    touch /shared/nameserver.ready

    echo "[$(hostname)] published current resolv.conf:"
    cat /shared/resolv.conf
    
else
    # ------------------------------------------------------------------
    # Plain router
    # ------------------------------------------------------------------


    echo "[$(hostname)] starting XIA router..."
    echo "[$(hostname)] waiting for nameserver router..."

    until [ -f /shared/nameserver.ready ]; do
        sleep 1
    done

    cp /shared/resolv.conf etc/resolv.conf

    echo "[$(hostname)] using nameserver:"
    cat etc/resolv.conf

    ./bin/xianet -r start || true

    echo "[$(hostname)] own router HID: $router_hid"


    fi

# ----------------------------------------------------------------------
# Determine this router's own HID.
# ----------------------------------------------------------------------

router_hid=$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^HID:/) { sub(/\)$/, "", $i); print $i; exit } }' etc/address.conf)

if [ -z "$router_hid" ]; then
    echo "[$(hostname)] unable to determine this router's own HID" >&2
    exit 1
fi

echo "[$(hostname)] own router HID: $router_hid"

# ----------------------------------------------------------------------
# Restore this router's HID as a LOCAL route.
#
# This is required even when the router has no local hosts. In particular,
# the nameserver needs a valid local route to its own HID.
# ----------------------------------------------------------------------

./bin/xroute -a "HID,${router_hid},-2"
echo "[$(hostname)] restored router self-route for $router_hid"

if [ -n "$XIA_PEER_HOSTS" ]; then
    # --------------------------------------------------------------
    # This router has locally attached hosts.
    # --------------------------------------------------------------

    echo "[$(hostname)] waiting for local peer hosts: $XIA_PEER_HOSTS"

    for n in $XIA_PEER_HOSTS; do
        until [ -s "/shared/dag_$n.txt" ]; do
            sleep 1
        done
    done

    echo "[$(hostname)] all local peer hosts are ready"

    # Bundle the currently published host DAGs.
    cat /shared/dag_*.txt > etc/hosts.xia

    echo "[$(hostname)] hosts.xia ready:"
    cat etc/hosts.xia

    # Host joining can replace the router's local HID route with a route
    # through port 0 whose next hop is the router itself. Restore it.
    ./bin/xroute -a "HID,${router_hid},-2"

    echo "[$(hostname)] restored router self-route for $router_hid after host joins"

else
    echo "[$(hostname)] no local peer hosts configured (transit router) -- skipping hosts.xia"
fi

./bin/xianet check || true

tail -f /dev/null
