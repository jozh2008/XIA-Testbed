# XIA Testbed: Failover Findings

## Summary

In the current Docker-based XIA testbed, stopping a router (graceful `node-off`) does **not** cause rerouting. Neighbors keep forwarding traffic to the dead router. `xping` and `xtraceroute` from host0 to server0 fail until the router is restored or the stale routes are removed by hand.

Why exactly this happens is **inferred, not confirmed**: I have not read the `xrouted` source, and a timed poll has not yet been run.

## Topology

- Four routers in a ring: `router0 - router1 - router2` and `router0 - router3 - router2`.
- `host0` is behind router0 (AD0). `server0` and `server1` are behind router2 (AD2).
- `router1` is also the nameserver.
- Both router paths are two hops (equal cost). Which one is active is decided at convergence and **changes between rebuilds**, so check `make xroute NODE=router0 | grep ad:` before each test and take down the router that is actually on the active path.

## What was tested

1. Converged state: every router has routes to every other AD; neighbors carry flag `00000004`.
2. `make node-off NODE=router3`, in a run where router3 was on the active path (so a valid failure test).
3. Inspected `xroute` on router0, router1 and router2, and ran `xping` / `xtraceroute` from host0 to server0.

## Observations

- Router0 sends the server's AD out port 0 via router3's HID (`066b...`).
- Router2 sends host0's AD out port 0 via the same HID.
- Tables were identical across checks taken minutes apart: stale router3 entries were never removed.
- `xtraceroute` stops at hop 1; `xping` returns `Time Exceeded` and then nothing.
- `xroute` on router3 reports "Unable to connect to Click" (expected after stop).

## Important clarification: the router1 path is not an installed alternative

A routing table holds one next hop per destination. Router0 has a single entry for the server AD (via router3). The path via router1 is only *implied*:

- router0 can reach router1 (port 2), and
- router1 can reach router2's AD (in router1's own table).

There is no entry in router0 saying "reach the server AD via router1". It would only appear if `xrouted` recomputed routes and replaced the current entry.

## Likely reasons (unverified)

1. **No neighbor timeout, or a very long one.** Neighbors get no "router3 is dead" message; they must infer it from missing hellos. Nothing was removed within the time waited.
2. **Router3 stays in the topology view.** If the link-state view is unchanged, the shortest-path result is unchanged.
3. **Equal-cost paths.** Even after a recompute, nothing makes router3 worse than router1 unless it is removed.
4. **Docker hides the failure.** The container stays up, so bridge interfaces never go down and no link-down event is generated.
5. `node-off` and `node-kill` (process-level) behave about the same from the neighbors' point of view: both just stop router3's processes.

## Not yet verified

- A timed poll (5-10 min) of router0's table for the router3 entries to see whether they ever expire.
- `xrouted` log lines about hellos or timeouts in `/var/log/syslog`.
- Whether `xroute -h` supports deleting routes, and whether `xrouted` then installs the router1 path.
- Other failure types: `docker compose pause`, `docker network disconnect`, `docker compose kill`.

## Commands for the remaining checks

```bash
# Timed expiry check
make node-kill NODE=router3
for i in $(seq 1 120); do date +%T; docker compose exec -T router0 xroute | grep -c 066b; sleep 5; done

# xrouted behavior
docker compose exec router0 grep -i xrouted /var/log/syslog | tail -30
docker compose exec router0 grep -rniE 'timeout|expire|hello|interval' /opt/xia-core/daemons/xrouted/ | head -30

# Other failure modes
docker compose pause router3 ; docker compose unpause router3
docker network disconnect <project>_net-r0-r3 router3
```

Interpretation: if the count drops to 0 at some point, that time is the failover delay. If it never drops, `xrouted` does not age out dead neighbors.

## Recovery

```bash
make node-on NODE=router3
```

Then check `make check` and `make xroute NODE=router3`. If router3's own HID route reads `0 00000004` instead of `-2 (self) 00000100`, re-add it with `xroute -a "HID,<HID>,-2"`.

## Next steps

1. Run the timed poll to confirm whether any expiry exists.
2. Read the `xrouted` source/config for hello and timeout parameters.
3. If there is no expiry: patch `xrouted`, or add an external monitor that removes stale routes and triggers a route update.

## Testbed notes learned along the way

- `CacheFilterSock` binds `/tmp/cachefilter-click.sock`; a stale file makes click fail with "Address already in use". Clean `/tmp/*.sock` on stop/start.
- `xianet stop` can leave an orphan `click` process; `pkill -9 -x click` clears it.
- Recreating containers (`make up`, `restart`, `reset`) generates new HIDs/ADs; use `node-off`/`node-on` to bounce nodes.
- Router self-route (`HID,<own HID>,-2`) can be overwritten shortly after start; `node-ctl.sh` re-applies it.
- `setsid nohup` redirects output to `nohup.out` when stdout is a TTY; use `setsid` alone so output reaches `docker compose logs`.
- `docker compose logs` shows only PID 1 output; XIA daemon logs go to `/var/log/syslog`.