+++
title = "Delivering Results to Other Tools"
description = "Probe endpoints through Burp/ZAP or export them to Elasticsearch."
weight = 1
sort_by = "weight"

+++

Noir splits "delivering results" into two distinct families:

- **PROBE** — fire HTTP requests at the endpoints noir just discovered (active replay, optionally through a proxy like Burp Suite or ZAP).
- **EXPORT** — ship the endpoint catalog to an external data store (e.g. Elasticsearch) as data, with no HTTP traffic to the endpoints themselves.

## Probe

Relevant flags:

| Flag | Purpose |
| --- | --- |
| `--probe` | Fire HTTP requests at each discovered endpoint (needs `-u`) |
| `--probe-via URL` | Route probes through this proxy URL |
| `--probe-header VAL` | Add a header to every probe (repeatable) |
| `--probe-match VAL` | Only probe endpoints matching the pattern (URL, method, or `method:URL`) |
| `--probe-skip VAL` | Skip endpoints matching the pattern |

### Replay through a proxy

Send every endpoint through a local Burp/ZAP proxy so its scanner picks them up.

```bash
noir scan ./source -u http://localhost:3000 --probe-via http://localhost:8080
```

![](./deliver-proxy.png)

### Custom headers

Attach an auth token or any other header to every probe.

```bash
noir scan ./source -u http://localhost:3000 \
  --probe-via http://localhost:8080 \
  --probe-header "Authorization: Bearer your-token"
```

![](./deliver-header.png)

### Match / skip

Narrow the set of endpoints sent through the proxy. Patterns accept a URL substring, an HTTP method (case-insensitive), or `method:URL` combined.

```bash
# Only API endpoints
noir scan ./source -u http://localhost:3000 --probe-via http://localhost:8080 --probe-match "api"

# Only GET requests
noir scan ./source -u http://localhost:3000 --probe-via http://localhost:8080 --probe-match "GET"

# Skip POST requests
noir scan ./source -u http://localhost:3000 --probe-via http://localhost:8080 --probe-skip "POST"

# POST requests to /api only
noir scan ./source -u http://localhost:3000 --probe-via http://localhost:8080 --probe-match "POST:/api"

# Skip GET requests to /admin
noir scan ./source -u http://localhost:3000 --probe-via http://localhost:8080 --probe-skip "GET:/admin"
```

Supported HTTP methods: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, TRACE, CONNECT.

Multiple `--probe-match` / `--probe-skip` flags compose:

```bash
noir scan ./source -u http://localhost:3000 \
  --probe-via http://localhost:8080 \
  --probe-match "GET" --probe-match "POST:/api"
```

![](./deliver-mf.png)

## Export

Push the endpoint catalog to an external data store. Categorically different from probing — no traffic hits the endpoints themselves.

```bash
noir scan ./source --export-es http://localhost:9200
```

## v0 aliases

The v0.x flag names continue to work — noir maps them silently:

| v0 flag | v1 equivalent |
| --- | --- |
| `--send-req` | `--probe` |
| `--send-proxy URL` | `--probe-via URL` |
| `--send-es URL` | `--export-es URL` |
| `--with-headers VAL` | `--probe-header VAL` |
| `--use-matchers VAL` | `--probe-match VAL` |
| `--use-filters VAL` | `--probe-skip VAL` |

Existing CI scripts and Dockerfiles using the v0 names don't need any changes. New documentation, examples, and shell completions surface the v1 names.
