+++
title = "Delivering Results to Other Tools"
description = "Learn how to use Noir's 'Deliver' feature to send discovered endpoints to other tools like Burp Suite, ZAP, or Elasticsearch for further analysis and security testing."
weight = 1
sort_by = "weight"

+++

Send discovered endpoints directly to security tools like Burp Suite, ZAP, or Elasticsearch for further analysis.

## Usage

Command-line flags:

*   `--send-req`: Send as web request
*   `--send-proxy http://proxy...`: Send through HTTP proxy
*   `--send-es http://es...`: Send to Elasticsearch
*   `--with-headers X-Header:Value`: Add custom headers
*   `--use-matchers string`: Only send matching endpoints (URL, method, or method:URL)
*   `--use-filters string`: Exclude matching endpoints (URL, method, or method:URL)

### Sending to a Proxy

Send all endpoints to proxy (e.g., Burp Suite, ZAP):

```bash
noir -b ./source --send-proxy http://localhost:8080
```

![](./deliver-proxy.png)

### Adding Custom Headers

Add custom headers (e.g., authentication tokens):

```bash
noir -b ./source --send-proxy http://localhost:8080 --with-headers "Authorization: Bearer your-token"
```

![](./deliver-header.png)

### Filtering and Matching

Send specific endpoints using matchers and filters:

#### URL-based Filtering
Send endpoints containing "api":

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-matchers "api"
```

#### Method-based Filtering
Send only GET requests:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-matchers "GET"
```

Exclude POST requests:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-filters "POST"
```

#### Method and URL Combination
Send POST requests to API endpoints:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-matchers "POST:/api"
```

Exclude GET requests to admin pages:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-filters "GET:/admin"
```

#### Supported HTTP Methods
GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, TRACE, CONNECT (case insensitive)

#### Multiple Patterns
Use multiple matchers or filters:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-matchers "GET" --use-matchers "POST:/api"
```

![](./deliver-mf.png)
