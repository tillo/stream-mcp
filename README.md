# stream-mcp

A small, self-contained image that puts [`@evertrust/stream-mcp`](https://github.com/evertrust/stream-mcp)
(the EverTrust Stream / PKI MCP server, which speaks **stdio**) on the network, so it can
be reached over HTTP by Claude Code, Cursor, and other MCP clients — instead of only
locally over stdio.

It wraps the upstream server with:

- [`supergateway`](https://github.com/supercorp-ai/supergateway) to expose it as
  **streamable HTTP / SSE**, and
- **nginx** for **bearer-token auth** (an `Authorization: Bearer <token>` header *or* a
  `?token=<token>` query param), so the endpoint can be published safely behind a reverse
  proxy.

The MCP package and supergateway are **baked into the image** — there is no runtime
`npm install`, so the container starts immediately and the versions are pinned and
reproducible.

## Notes

- stream-mcp runs **stateless** — no per-session auth cache, so memory stays flat and no
  `--stateful` / session-timeout tuning is needed.
- nginx rewrites `Host`/`Origin` to `localhost` and strips `Sec-Fetch-*` headers, because
  the MCP server validates the request origin.

## Run

```bash
docker run -d \
  -p 8080:8080 \
  -e STREAM_URL=https://stream.example.com \
  -e STREAM_API_ID=<api id> \
  -e STREAM_API_IDPROV=local \
  -e STREAM_API_KEY=<api key> \
  -e MCP_BEARER_TOKEN=<a long random secret> \
  ghcr.io/<your-org>/stream-mcp:latest
```

Then point your MCP client at `https://<host>:8080/`, sending
`Authorization: Bearer <MCP_BEARER_TOKEN>` (or appending `?token=<MCP_BEARER_TOKEN>`).

### Environment

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `MCP_BEARER_TOKEN` | yes | — | Gate token (header or `?token=`) |
| `STREAM_URL` | yes | — | Stream base URL the MCP calls |
| `STREAM_API_ID` | yes | — | Stream API identifier |
| `STREAM_API_IDPROV` | yes | — | Stream API identity provider (e.g. `local`) |
| `STREAM_API_KEY` | yes | — | Stream API key |
| `SUPERGATEWAY_FLAGS` | no | _(empty)_ | Extra supergateway flags |
| `LISTEN_PORT` | no | `8080` | Public (gate) port |
| `INTERNAL_PORT` | no | `9090` | Bridge (loopback) port |

## Build

```bash
docker build -t stream-mcp .
# pin a different upstream version:
docker build --build-arg MCP_VERSION=1.0.1 -t stream-mcp .
```

`CACHEBUST_DAY` (a date stamp) is passed by CI to force a daily `apt upgrade` layer so the
base image keeps current security patches.

## License

MIT — see [LICENSE](LICENSE).
