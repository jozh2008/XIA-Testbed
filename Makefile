COMPOSE := docker compose
IMAGE := xia-core:v2

NODES := router0 router1 router2 host0 server0 server1

.PHONY: all
.PHONY: build rebuild up down reset restart
.PHONY: status logs check
.PHONY: shell-host0 shell-server0 shell-server1 shell-router0 shell-router1 shell-router2
.PHONY: xdag xroute


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


# ============================================================
# XIA information
# ============================================================

xdag:
	@test -n "$(NODE)" || (echo "Usage: make xdag NODE=host0"; exit 1)
	$(COMPOSE) exec $(NODE) xdag

xroute:
	@test -n "$(NODE)" || (echo "Usage: make xroute NODE=host0"; exit 1)
	$(COMPOSE) exec $(NODE) xroute
