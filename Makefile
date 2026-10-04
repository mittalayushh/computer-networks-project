# ============================================================
# CN Phase 1 - Team 1
#
# Mac 1 -> DNS Server
# Mac 2 -> nginx HTTPS Load Balancer
# Mac 3 -> Backend A
# Mac 4 -> Backend B
# ============================================================

SHELL := /bin/bash

PROJECT_DIR := $(shell pwd)

BACKEND_FILE := $(PROJECT_DIR)/backend/backend.py
NGINX_CONF := $(PROJECT_DIR)/configs/nginx.conf
DNSMASQ_CONF := $(PROJECT_DIR)/configs/dnsmasq.conf

DOMAIN := app.team1.test
HTTPS_PORT := 8443

# ------------------------------------------------------------
# HELP
# ------------------------------------------------------------

.PHONY: help
help:
	@echo ""
	@echo "CN Phase 1 - Team 1"
	@echo "============================================"
	@echo ""
	@echo "Backend:"
	@echo "  make backend-a       Start Backend A on port 3001"
	@echo "  make backend-b       Start Backend B on port 3002"
	@echo ""
	@echo "nginx (Mac 2):"
	@echo "  make nginx-test      Validate nginx configuration"
	@echo "  make nginx-start     Start nginx"
	@echo "  make nginx-reload    Reload nginx configuration"
	@echo "  make nginx-stop      Stop nginx"
	@echo "  make nginx-status    Check port 8443"
	@echo ""
	@echo "DNS (Mac 1):"
	@echo "  make dns-start       Start dnsmasq"
	@echo "  make dns-stop        Stop dnsmasq"
	@echo "  make dns-status      Check DNS port 53"
	@echo ""
	@echo "Testing:"
	@echo "  make test-dns        Test private DNS"
	@echo "  make test-https      Test HTTPS"
	@echo "  make test-balance    Send 6 load-balanced requests"
	@echo "  make test-cache      Show cache headers"
	@echo "  make test-etag       Test ETag / 304 response"
	@echo ""
	@echo "  make demo            Run main client-side tests"
	@echo ""


# ------------------------------------------------------------
# BACKENDS
# ------------------------------------------------------------

.PHONY: backend-a
backend-a:
	@echo "Starting Backend A on port 3001..."
	BACKEND=A PORT=3001 python3 $(BACKEND_FILE)


.PHONY: backend-b
backend-b:
	@echo "Starting Backend B on port 3002..."
	BACKEND=B PORT=3002 python3 $(BACKEND_FILE)


# ------------------------------------------------------------
# NGINX - RUN THESE ON MAC 2
# ------------------------------------------------------------

.PHONY: nginx-test
nginx-test:
	@echo "Testing nginx configuration..."
	nginx -t -c "$(NGINX_CONF)"


.PHONY: nginx-start
nginx-start: nginx-test
	@echo "Starting nginx..."
	nginx -c "$(NGINX_CONF)"


.PHONY: nginx-reload
nginx-reload: nginx-test
	@echo "Reloading nginx..."
	nginx -s reload -c "$(NGINX_CONF)"


.PHONY: nginx-stop
nginx-stop:
	@echo "Stopping nginx..."
	-nginx -s stop -c "$(NGINX_CONF)"


.PHONY: nginx-status
nginx-status:
	@echo "Checking HTTPS listener..."
	@lsof -nP -iTCP:$(HTTPS_PORT) -sTCP:LISTEN || \
		echo "Nothing is listening on port $(HTTPS_PORT)"


# ------------------------------------------------------------
# DNSMASQ - RUN THESE ON MAC 1
# ------------------------------------------------------------

.PHONY: dns-start
dns-start:
	@echo "Starting dnsmasq..."
	@if [ -f /tmp/team1-dnsmasq.pid ]; then \
		sudo kill "$$(cat /tmp/team1-dnsmasq.pid)" 2>/dev/null || true; \
		rm -f /tmp/team1-dnsmasq.pid; \
	fi
	sudo "$$(brew --prefix dnsmasq)/sbin/dnsmasq" \
		--conf-file="$(DNSMASQ_CONF)" \
		--pid-file=/tmp/team1-dnsmasq.pid
	@echo "dnsmasq started."


.PHONY: dns-stop
dns-stop:
	@echo "Stopping dnsmasq..."
	@if [ -f /tmp/team1-dnsmasq.pid ]; then \
		sudo kill "$$(cat /tmp/team1-dnsmasq.pid)" 2>/dev/null || true; \
		rm -f /tmp/team1-dnsmasq.pid; \
		echo "dnsmasq stopped."; \
	else \
		echo "dnsmasq PID file not found."; \
	fi


.PHONY: dns-status
dns-status:
	@echo "Checking DNS port 53..."
	@sudo lsof -nP -iUDP:53 || \
		echo "No UDP DNS service detected on port 53."


# ------------------------------------------------------------
# CLIENT TESTS
# ------------------------------------------------------------

.PHONY: test-dns
test-dns:
	@echo ""
	@echo "Testing private DNS..."
	@echo "--------------------------------------------"
	dig $(DOMAIN)


.PHONY: test-public-dns
test-public-dns:
	@echo ""
	@echo "Testing public DNS. Expected result: NXDOMAIN"
	@echo "--------------------------------------------"
	dig @8.8.8.8 $(DOMAIN)


.PHONY: test-https
test-https:
	@echo ""
	@echo "Testing HTTPS..."
	@echo "--------------------------------------------"
	curl -v https://$(DOMAIN):$(HTTPS_PORT)/


.PHONY: test-status
test-status:
	@echo ""
	curl -i https://$(DOMAIN):$(HTTPS_PORT)/api/status


.PHONY: test-balance
test-balance:
	@echo ""
	@echo "Testing nginx load balancing..."
	@echo "--------------------------------------------"
	@for i in {1..6}; do \
		printf "Request $$i: "; \
		curl -s -D - https://$(DOMAIN):$(HTTPS_PORT)/api/status \
			-o /dev/null \
			| tr -d '\r' \
			| grep -i '^X-Backend:'; \
	done


.PHONY: test-cache
test-cache:
	@echo ""
	@echo "Testing HTTP caching headers..."
	@echo "--------------------------------------------"
	curl -sI https://$(DOMAIN):$(HTTPS_PORT)/cache-demo


.PHONY: test-etag
test-etag:
	@echo ""
	@echo "Testing ETag conditional request..."
	@echo "Expected response: HTTP 304 Not Modified"
	@echo "--------------------------------------------"
	curl -i \
		-H 'If-None-Match: "team1-cache-v1"' \
		https://$(DOMAIN):$(HTTPS_PORT)/cache-demo


# ------------------------------------------------------------
# DEMO
# ------------------------------------------------------------

.PHONY: demo
demo:
	@echo ""
	@echo "========== DNS =========="
	dig $(DOMAIN)
	@echo ""
	@echo "========== HTTPS =========="
	curl -s -i https://$(DOMAIN):$(HTTPS_PORT)/api/status
	@echo ""
	@echo "========== LOAD BALANCING =========="
	@for i in {1..6}; do \
		printf "Request $$i: "; \
		curl -s -D - https://$(DOMAIN):$(HTTPS_PORT)/api/status \
			-o /dev/null \
			| tr -d '\r' \
			| grep -i '^X-Backend:'; \
	done
	@echo ""
	@echo "========== CACHE =========="
	curl -sI https://$(DOMAIN):$(HTTPS_PORT)/cache-demo