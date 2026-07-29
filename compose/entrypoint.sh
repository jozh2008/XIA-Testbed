#!/bin/bash
set -e

service rsyslog start

cd /opt/xia-core

ROLE="${ROLE:?ROLE env var must be 'router' or 'host'}"
NAMESERVER="${NAMESERVER:-false}"
AD_NAME="${AD_NAME:-unknown-ad}"
ALL_NODES="${ALL_NODES:?ALL_NODES env var must list every node hostname}"

SHARED_DIR=/shared
DAG_DIR="${SHARED_DIR}/dags"
RESOLV_SRC=etc/resolv.conf
RESOLV_SHARED="${SHARED_DIR}/resolv.conf"
HOSTS_SRC=etc/hosts.xia

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

if [ "$ROLE" = "host" ]; then
mkdir -p "$DAG_DIR"
me="$(hostname)"

echo "[xia:${AD_NAME}] waiting for network join to complete before running xdag..."
set +e
attempts=0
max_attempts=60
dag_line=""
while [ $attempts -lt $max_attempts ]; do
dag_line="$(bin/xdag 2>&1)"
xdag_rc=$?
if [ "$xdag_rc" -eq 0 ] && [ -n "$dag_line" ]; then
break
fi
attempts=$((attempts+1))
sleep 1
done
set -e

if [ "$xdag_rc" -ne 0 ] || [ -z "$dag_line" ]; then
echo "[xia:${AD_NAME}] xdag never succeeded after ${max_attempts}s, last output: $dag_line"
else
echo "[xia:${AD_NAME}] xdag succeeded after ${attempts}s: $dag_line"
tmp="$(mktemp "${DAG_DIR}/.tmp.XXXXXX")"
echo "$dag_line" > "$tmp"
mv "$tmp" "${DAG_DIR}/${me}"
echo "[xia:${AD_NAME}] published DAG to ${DAG_DIR}/${me}"
fi

echo "[xia:${AD_NAME}] waiting for DAGs of: ${ALL_NODES}"
for n in $ALL_NODES; do
until [ -s "${DAG_DIR}/${n}" ]; do sleep 1; done
done

: > "$HOSTS_SRC"
for n in $ALL_NODES; do
cat "${DAG_DIR}/${n}" >> "$HOSTS_SRC"
done
echo "[xia:${AD_NAME}] hosts.xia populated, xping by name should work now."
else
echo "[xia:${AD_NAME}] router node, skipping hosts.xia registration."
fi

touch /var/log/syslog
exec tail -f /var/log/syslog 