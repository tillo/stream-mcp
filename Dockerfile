# stream-mcp: wraps @evertrust/stream-mcp (stdio) with supergateway (streamable
# HTTP/SSE) behind an nginx bearer-token gate — a single self-contained image, so
# the MCP can be reached over the network instead of only locally over stdio.
#
# Public default pulls node:24-trixie-slim straight from Docker Hub. In CI with a
# registry pull-through cache (e.g. the GitLab dependency proxy), pass
#   --build-arg REGISTRY=<cache-prefix>/
# to route the base image through it.
ARG REGISTRY=
FROM ${REGISTRY}node:26-trixie-slim

# CACHEBUST_DAY (CI passes $(date +%Y%m%d)) invalidates this layer once per day so
# `apt upgrade` picks up freshly-published security patches.
ARG CACHEBUST_DAY=unset
RUN echo "cache day: ${CACHEBUST_DAY}" && \
    apt-get update && apt-get -y upgrade && \
    apt-get install -y --no-install-recommends \
      nginx gettext-base tini ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Bake supergateway + the MCP package so there is NO runtime `npm install` (the live
# deployment used to install on every pod start — ~38s plus node-engine warnings).
# Both are pinned with a `# renovate:` line (renovate.json, infra-ik4p.1): supergateway
# used to be `latest`, which every daily CACHEBUST rebuild moved without an MR.
# renovate: datasource=npm depName=supergateway
ARG SUPERGATEWAY_VERSION=4.2.1
ARG MCP_PACKAGE=@evertrust/stream-mcp
# renovate: datasource=npm depName=@evertrust/stream-mcp
ARG MCP_VERSION=1.0.2
# node:24's bundled npm carries its OWN dependency tree (tar, brace-expansion,
# ip-address) that drifts onto grype-flagged HIGH/CRITICAL versions. Upgrade npm
# in-place first so those bundled deps land on patched versions (npm 11.20.0
# bundles tar@7.5.22, brace-expansion@5.0.9, ip-address@10.5.0).
# renovate: datasource=npm depName=npm
ARG NPM_VERSION=12.2.1
RUN npm install -g "npm@${NPM_VERSION}" && \
    npm install -g "supergateway@${SUPERGATEWAY_VERSION}" "${MCP_PACKAGE}@${MCP_VERSION}" && \
    npm cache clean --force

# Declare the meaningful version (consumed by the optional CI version-tag job).
RUN echo "${MCP_VERSION}" > /etc/image-version

WORKDIR /app
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Runtime knobs (override at deploy):
#   MCP_BEARER_TOKEN    (required) gate token — Authorization: Bearer <t>  or  ?token=<t>
#   MCP_BIN             stdio binary supergateway runs
#   SUPERGATEWAY_FLAGS  extra supergateway flags
#   LISTEN_PORT         gate (public) port
#   INTERNAL_PORT       bridge (loopback) port
# stream-mcp runs stateless (no per-session auth cache), so memory stays flat and no
# --stateful/--sessionTimeout is needed.
# Supply the upstream API env the MCP itself reads (STREAM_URL, STREAM_API_ID,
# STREAM_API_IDPROV, STREAM_API_KEY) at runtime — never bake credentials into the image.
ENV MCP_BIN=stream-mcp \
    SUPERGATEWAY_FLAGS="" \
    LISTEN_PORT=8080 \
    INTERNAL_PORT=9090 \
    HOME=/tmp \
    npm_config_cache=/tmp/.npm

# Smoke test (fails the build): bridge the MCP exactly as start.sh does and speak to
# it as a 2025-11-25 client — initialize, then tools/list must return tools. An MCP
# release that refuses supergateway's initialize handshake (@evertrust/horizon-mcp
# 3.x did: 2026-07-28-only) builds and starts fine yet serves nothing. The STREAM_*
# values are dummies: stream-mcp authenticates on the first tool call, not at start.
COPY smoke.mjs /app/smoke.mjs
RUN STREAM_URL=https://127.0.0.1:9 STREAM_API_ID=smoke STREAM_API_IDPROV=smoke STREAM_API_KEY=smoke; \
    export STREAM_URL STREAM_API_ID STREAM_API_IDPROV STREAM_API_KEY; \
    supergateway --stdio "${MCP_BIN}" --outputTransport streamableHttp --port 9099 \
      ${SUPERGATEWAY_FLAGS} >/tmp/smoke-gateway.log 2>&1 & gw=$!; \
    node /app/smoke.mjs 9099; rc=$?; kill "$gw"; \
    [ "$rc" = 0 ] || tail -20 /tmp/smoke-gateway.log; rm -f /tmp/smoke-gateway.log; exit "$rc"

EXPOSE 8080
ENTRYPOINT ["/usr/bin/tini", "--", "/app/start.sh"]
