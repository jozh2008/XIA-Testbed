#!/bin/bash
set -e

# Start syslog daemon to create /dev/log socket for xnetjd
service rsyslog start

cd /opt/xia-core

# ROLE       = router | host
# NAMESERVER = true on exactly ONE router in the ENTIRE testbed
#              (xia-core's mainline branches support only one nameserver
#              for the whole flat network)
ROLE="${ROLE:?ROLE env var must be 'router' or 'host'}"
NAMESERVER="${NAMESERVER:-false}"
AD_NAME="${AD_NAME:-unknown-ad}"

SHARED_DIR=/shared
RESOLV_SRC=etc/resolv.conf
RESOLV_SHARED="${SHARED_DIR}/resolv.conf"

IFACE_FLAG=""
if [ -n "$IGNORE_IFACES" ]; then
  IFACE_FLAG="-f${IGNORE_IFACES}"
fi

echo "[xia:${AD_NAME}] role=${ROLE} nameserver=${NAMESERVER} host=$(hostname)"

if [ "$ROLE" = "router" ] && [ "$NAMESERVER" = "true" ]; then
  bin/xianet -r -n $IFACE_FLAG start
  mkdir -p "$SHARED_DIR"
  cp "$RESOLV_SRC" "$RESOLV_SHARED"

elif [ "$ROLE" = "router" ]; then
  until [ -f "$RESOLV_SHARED" ]; do sleep 1; done
  cp "$RESOLV_SHARED" "$RESOLV_SRC"
  bin/xianet -r $IFACE_FLAG start

elif [ "$ROLE" = "host" ]; then
  until [ -f "$RESOLV_SHARED" ]; do sleep 1; done
  cp "$RESOLV_SHARED" "$RESOLV_SRC"
  bin/xianet -t $IFACE_FLAG start

else
  echo "Unknown ROLE=$ROLE" >&2
  exit 1
fi

echo "[xia:${AD_NAME}] node up."

# Keep container alive and stream daemon logs to standard output
touch /var/log/syslog
exec tail -f /var/log/syslog