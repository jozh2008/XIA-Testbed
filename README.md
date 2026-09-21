# XIA testbed

The testbed uses Docker Compose with the XIA Core image:

```bash
COMPOSE := docker compose
IMAGE := xia-core:v2
```

The available nodes are:

```bash
router0 router1 router2 host0 server0 server1
```


## 1. Initialize the Network

The Makefile provides several commands for managing the Docker testbed.

### Reset the Environment

First, remove any stale containers, volumes, and orphaned services and delete previous packet captures:

```bash
make reset
```


This executes:
```bash
docker compose down -v --remove-orphans
rm -f captures/*.pcap
```
### Rebuild the XIA Images

For a clean build without using Docker's build cache:

```bash
make rebuild
```

This runs:

```bash
docker compose build --no-cache
```

Note: A normal cached build is also available with make build.

Start the Network

Launch the complete topology in detached mode:

```bash
make up
```

This runs:
```bash
docker compose up -d --build
```

The typical clean initialization sequence is therefore:

```bash
make reset
make rebuild
make up
```

Wait approximately 20 seconds for the routers and nameserver to synchronize their DAGs.

## 2. Verify Network Readiness

The Makefile provides a check target that runs the XIA network diagnostic on every node.

Run:

```bash
make check
```

The command checks:

```bash
router0
router1
router2
host0
server0
server1
```

The underlying command is:

```bash
/opt/xia-core/bin/xianet check
```

You can also inspect the running Docker containers with:

```bash
make status
```

For live Docker Compose logs:

```bash
make logs
```

If the network needs to be restarted, use:
```bash
make restart
```

## 3. Inspect the XIA Network

Before performing the file transfer, you can inspect the XIA topology and routing information.
View the DAG

The `xdag` target requires a `NODE` argument.

For example, to inspect `host0`:
```bash
make xdag NODE=host0
```

You can inspect any of the available nodes, for example:
```bash
make xdag NODE=router0
make xdag NODE=router1
make xdag NODE=router2
make xdag NODE=server0
make xdag NODE=server1
```

The underlying command is:
```bash
docker compose exec <NODE> xdag
```

### View XIA Routes

Similarly, use xroute to inspect the routing table of a node:

```bash
make xroute NODE=host0
```

For example:
```bash
make xroute NODE=router0
make xroute NODE=router1
make xroute NODE=router2
make xroute NODE=server0
make xroute NODE=server1
```

These commands are useful for confirming that the XIA DAG and routing state have propagated before testing CID-based file retrieval.
## 4. Start the XFTP Server (server0)

Use the Makefile shortcut to enter the server0 container:

```bash
make shell-server0
```

Once inside the `server0` container, move to the XFTP application directory:

```bash
cd /opt/xia-core/applications/xftp/
```

Create the test file:

```bash
echo "This file is routed by its hash, not its location." > cid_test.txt
```

Start the XFTP daemon in the background:

```bash
./xftpd &
```

The server is now ready to provide the test file.

You can leave the shell open, or press Ctrl+D to exit. The daemon will continue running in the background.
## 5. Fetch the File via CID (host0)

Open a new terminal on the host machine.

Enter the host0 container using:

```bash
make shell-host0
```

Inside the `host0` container, move to the XFTP application directory:

```bash
cd /opt/xia-core/applications/xftp/
```

Start the XFTP client in verbose mode:

```bash
./xftp -v
```

The `-v` option allows you to observe the XIA routing and XFTP protocol activity.

At the interactive `>>` prompt, execute:

```bash
get cid_test.txt downloaded_test.txt
```

## 6. Expected CID Routing Behavior

During the transfer, verbose output should expose the XIA content-based routing process.

Conceptually, the sequence is:

```bash
host0
  |
  | Query basicftp.xia
  | using Service ID (SID)
  v
XFTP Service
  |
  | File metadata / chunk list
  | containing Content ID (CID)
  v
CID:f3e48129...
  |
  | XIA CID routing
  v
Content / Cache
  |
  v
downloaded_test.txt
```

The important distinction from conventional IP-based file transfer is that the content is identified by its Content ID (CID) rather than by the network location of the server.

You should see behavior corresponding to:

1. The client queries `basicftp.xia` using a Service ID (SID).
2. The server returns a chunk list containing the file's Content ID (CID).
3. The client requests the content using the CID.
4. XIA routes the request according to the content identifier.
5. The requested content can be satisfied from an appropriate local cache or content source rather than requiring a traditional IP socket connection to the original server.

The exact CID value will depend on the content and environment. For example:

```bash
CID:f3e48129...
```

## 7. Verify the Download

After the transfer completes, exit the XFTP interactive prompt:
```bash
quit
```

Then verify that the file was downloaded:
```bash
cat downloaded_test.txt
```

The expected output is:
```bash
This file is routed by its hash, not its location.
```

You can also confirm that the file exists with:

```bash
ls -l downloaded_test.txt
```

## 8. Makefile Command Reference

The provided Makefile exposes the following commands:
| Command | Purpose |
| :--- | :--- |
| `make` | Start the network via the default `up` target |
| `make build` | Build Docker images using the cache |
| `make rebuild` | Rebuild Docker images without the cache |
| `make up` | Start the Docker Compose topology |
| `make down` | Stop and remove the topology |
| `make reset` | Remove containers, volumes, orphans, and packet captures |
| `make restart` | Stop and start the topology |
| `make status` | Display Docker Compose container status |
| `make logs` | Follow Docker Compose logs |
| `make check` | Run `xianet check` on every node |
| `make shell-host0` | Open a shell on `host0` |
| `make shell-server0` | Open a shell on `server0` |
| `make shell-server1` | Open a shell on `server1` |
| `make shell-router0` | Open a shell on `router0` |
| `make shell-router1` | Open a shell on `router1` |
| `make shell-router2` | Open a shell on `router2` |
| `make xdag NODE=<node>` | Display the XIA DAG for a node |
| `make xroute NODE=<node>` | Display XIA routes for a node |
