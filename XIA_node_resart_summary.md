# XIA Testbed: Node Restart Problems with the Original Makefile Targets

## Summary

With the original `node-off`, `node-kill` and `node-on` targets, a stopped node does not come back. `node-on` prints `running` for every daemon, but a later `make check` shows them all stopped. The replacement is `scripts/node-ctl.sh` (`on | off | kill`), which gets nodes back reliably.

Causes below are marked as confirmed or inferred. The `xianet` and `xrouted` sources were not read.

## Original targets

```make
node-off:
	$(COMPOSE) exec $(NODE) /opt/xia-core/bin/xianet stop

node-kill:
	$(COMPOSE) exec $(NODE) /opt/xia-core/bin/xianet kill

node-on:
	$(COMPOSE) exec $(NODE) bash -c 'if [ "$$XIA_NAMESERVER" = "1" ]; then /opt/xia-core/bin/xianet -r -n start; elif [[ "$(NODE)" == router* ]]; then /opt/xia-core/bin/xianet -r start; else /opt/xia-core/bin/xianet -t start; fi'
```

## What happened

- `make node-off` stopped the daemons. On router3 it also reported `Orphan click process found`.
- `make node-on` printed `click: running`, `xrouted: running`, and so on.
- The next `make check` showed every daemon on that node stopped, so the node never really came back. This happened on router3 and again on router1.
- On router3, a manual `xianet -r start` then failed with `bind: Address already in use` for `CacheFilterSock`.
- On router1, `node-on` also printed several `dag_string(): could not find source and/or sink` warnings. Their meaning was not investigated.
- `xping` fails while the node is down, and the node cannot be turned back on with the original `node-on`.

## Causes

| Cause | Status |
|---|---|
| **Stale socket.** `CacheFilterSock` binds `/tmp/cachefilter-click.sock`. `xianet stop` leaves the file behind, and the new click cannot bind and dies. The startup scripts clean only `/tmp/xsocket*`, `/tmp/icid*`, `/tmp/xcache*`, `/tmp/click*`, which does not match this file. | Confirmed on router3 (removing the file fixed the start). Same pattern on router1, not separately confirmed. |
| **Orphan click.** `xianet stop` can leave a `click` process that `xianet kill` does not find ("nothing to kill"). | Seen on router3 (`Orphan click process found`). Later `ps` showed no leftover process, so the stale socket was the blocker there. |
| **Started inside an `exec` session.** The daemons are children of a throwaway `docker compose exec` (with a TTY), not of PID 1. | Unconfirmed. After the socket fix, router3 stayed up once the session ended. |
| **No self-route restore.** The own-HID route can be overwritten a few seconds after start (`0 00000004` instead of `-2 (self) 00000100`). The boot script restores it; the original `node-on` does not. | Confirmed on router3. A manual restore stayed for 60 s. |
| **No DAG or resolver republish.** The boot script republishes the router DAG, and on the nameserver, `resolv.conf`. The original `node-on` does neither. | Observed from the scripts. |
| **Output not in `docker compose logs`.** `logs` shows only PID 1 output, so anything started through `exec` is invisible there. XIA daemon logs go to `/var/log/syslog`. | Confirmed. |

## Fix: `scripts/node-ctl.sh`

- **`off`**: `xianet stop`, then hard cleanup (`pkill -9 -x click`, remove `/tmp/*.sock` and the other temp files).
- **`kill`**: SIGKILL the daemons and click, with no cleanup, to simulate a crash.
- **`on`**:
  - hard cleanup;
  - start with `setsid ./bin/xianet $FLAGS start > /proc/1/fd/1 2>&1 < /dev/null &`;
  - wait for click;
  - restore the self-route once the overwrite has appeared;
  - on the nameserver, republish `resolv.conf`;
  - republish the DAG.

Use `setsid` without `nohup`. When stdout is a TTY, `nohup` ignores the redirect and writes `nohup.out` instead, so the daemon output never reaches `docker compose logs`.

Makefile targets:

```make
node-off:
	$(require_node)
	$(COMPOSE) exec -T $(NODE) /opt/xia-core/scripts/node-ctl.sh off

node-kill:
	$(require_node)
	$(COMPOSE) exec -T $(NODE) /opt/xia-core/scripts/node-ctl.sh kill

node-on:
	$(require_node)
	$(COMPOSE) exec -T $(NODE) /opt/xia-core/scripts/node-ctl.sh on
```

The script must exist in the containers: either `COPY scripts/ /opt/xia-core/scripts/` in the Dockerfile, or a bind mount of `./scripts`. Also add `/tmp/*.sock` to the `rm -f` line in `start-router.sh` and `start-node.sh`.

## Result

With `node-ctl.sh`, `node-off` / `node-on` cycles on router3 and router1 came back with all daemons running.

## Still to check

- Whether `nohup.out` files from earlier runs still exist (`rm -f /opt/xia-core/nohup.out`).
- Whether the `dag_string()` warnings on router1 are harmless.
- The nameserver restart path: router3 listed `xnameservice` in the latest `make check`, so confirm which router is the nameserver after changes to `XIA_NAMESERVER`.

## Other notes

- Recreating containers (`make up`, `restart`, `reset`) generates new HIDs and ADs. Bounce nodes with `node-off` / `node-on` instead.
- Makefile recipe lines need real tab characters.