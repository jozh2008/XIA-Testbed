#!/bin/bash
# Usage: node-ctl.sh on|off|kill
# Runs inside a container via `docker compose exec -T`.

cd /opt/xia-core
HOST=$(hostname)

log() { echo "[$HOST] $*" | tee /proc/1/fd/1; }

# Role comes from the same env var / hostname convention as the startup scripts.
if [ "$XIA_NAMESERVER" = "1" ]; then FLAGS="-r -n"
elif [[ "$HOST" == router* ]];  then FLAGS="-r"
else                                  FLAGS="-t"
fi

hard_cleanup() {
    ./bin/xianet kill >/dev/null 2>&1 || true
    pkill -9 -x click 2>/dev/null     || true   # orphan that `xianet stop` leaves behind
    rm -f /tmp/xsocket* /tmp/icid* /tmp/xcache* /tmp/click* /tmp/*.sock
}

case "$1" in
off)
    log "node-off: graceful stop"
    ./bin/xianet stop >/dev/null 2>&1 || true
    hard_cleanup
    ./bin/xianet check 2>&1 | tee /proc/1/fd/1
    ;;

kill)
    log "node-kill: forceful stop"
    hard_cleanup
    ./bin/xianet check 2>&1 | tee /proc/1/fd/1
    ;;

on)
    log "node-on: starting XIA ($FLAGS)"
    hard_cleanup

    # Detach from the exec session so the daemons don't depend on its TTY.
    setsid nohup ./bin/xianet $FLAGS start > /proc/1/fd/1 2>&1 < /dev/null &

    # Wait for click to come up (max 60s).
    for i in $(seq 1 60); do
        ./bin/xianet check 2>/dev/null | grep -q '^click: *running' && break
        sleep 1
    done
    ./bin/xianet check 2>/dev/null | grep -q '^click: *running' \
        || { log "node-on: click did not start"; exit 1; }

    if [[ "$HOST" == router* ]]; then
        HID=$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^HID:/) { sub(/\)$/, "", $i); print $i; exit } }' etc/address.conf)
        [ -n "$HID" ] || { log "node-on: cannot determine HID"; exit 1; }
        ./bin/xroute -a "HID,${HID},-2"
        # Wait up to 30s for the overwrite to appear, then fix it once more.
        for i in $(seq 1 30); do
            if ./bin/xroute | grep -E "^HID +hid:${HID#HID:}" | grep -q ' 0 .*00000004'; then
                ./bin/xroute -a "HID,${HID},-2"
                log "re-restored self-route for $HID after overwrite"
                break
            fi
            sleep 1
        done
    fi

    # Nameserver router: republish the regenerated resolver config.
    if [ "$XIA_NAMESERVER" = "1" ]; then
        until [ -f etc/resolv.conf ]; do sleep 1; done
        cp etc/resolv.conf /shared/resolv.conf
        touch /shared/nameserver.ready
        log "republished resolv.conf"
    fi

    # Republish this node's DAG so peers' hosts.xia stays valid.
    until xdag > /shared/dag_$HOST.txt 2>/dev/null && [ -s /shared/dag_$HOST.txt ]; do
        sleep 1
    done
    log "node-on: done"
    ./bin/xianet check 2>&1 | tee /proc/1/fd/1
    ;;

*)
    echo "Usage: $0 on|off|kill" >&2; exit 2 ;;
esac