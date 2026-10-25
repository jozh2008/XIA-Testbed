COMPOSE := docker compose
IMAGE := xia-core:v2

NODES := router0 router1 router2 host0 server0 server1 router3

.PHONY: all
.PHONY: build rebuild up down reset restart
.PHONY: status logs check
.PHONY: shell-host0 shell-server0 shell-server1 shell-router0 shell-router1 shell-router2 shell-router3
.PHONY: node-off node-on node-bounce node-kill
.PHONY: xdag xroute

define require_node
	@test -n "$(NODE)" || { echo "Usage: make $@ NODE=<node>"; exit 1; }
	@echo "$(NODES)" | tr ' ' '\n' | grep -qx "$(NODE)" || { echo "Unknown node '$(NODE)'. Valid: $(NODES)"; exit 1; }
endef


# ============================================================
# Default
# ============================================================

all: up


# ============================================================
# Build
# ============================================================

build:
	$(COMPOSE) build

rebuild:
	$(COMPOSE) build --no-cache


# ============================================================
# Lifecycle
# ============================================================

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

reset:
	$(COMPOSE) down -v --remove-orphans
	rm -f captures/*.pcap

restart:
	$(MAKE) down
	$(MAKE) up


# ============================================================
# Diagnostics
# ============================================================

status:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f

check:
	@for node in $(NODES); do \
		echo ""; \
		echo "================ $$node ================"; \
		$(COMPOSE) exec -T $$node /opt/xia-core/bin/xianet check || true; \
	done


# ============================================================
# Interactive shells
# ============================================================

shell-host0:
	$(COMPOSE) exec host0 bash

shell-server0:
	$(COMPOSE) exec server0 bash

shell-server1:
	$(COMPOSE) exec server1 bash

shell-router0:
	$(COMPOSE) exec router0 bash

shell-router1:
	$(COMPOSE) exec router1 bash

shell-router2:
	$(COMPOSE) exec router2 bash

shell-router3:
	$(COMPOSE) exec router3 bash


# ============================================================
# XIA information
# ============================================================

xdag:
	@test -n "$(NODE)" || (echo "Usage: make xdag NODE=host0"; exit 1)
	$(COMPOSE) exec $(NODE) xdag

xroute:
	@test -n "$(NODE)" || (echo "Usage: make xroute NODE=host0"; exit 1)
	$(COMPOSE) exec $(NODE) xroute


# ============================================================
# Per-node control (failover testing)
#
#   make node-off    NODE=router3   graceful stop
#   make node-kill   NODE=router3   forceful stop
#   make node-on     NODE=router3   graceful start
#   make node-bounce NODE=router3   off, then on
# ============================================================



node-off:
	$(require_node)
	$(COMPOSE) exec -T $(NODE) /opt/xia-core/scripts/node-ctl.sh off

node-kill:
	$(require_node)
	$(COMPOSE) exec -T $(NODE) /opt/xia-core/scripts/node-ctl.sh kill

node-on:
	$(require_node)
	$(COMPOSE) exec -T $(NODE) /opt/xia-core/scripts/node-ctl.sh on

node-bounce:
	$(require_node)
	$(MAKE) node-off NODE=$(NODE)
	$(MAKE) node-on NODE=$(NODE)