+++
title = "Delivering Results to Other Tools"
description = "Learn how to use Noir's 'Deliver' feature to send discovered endpoints to other tools like Burp Suite, ZAP, or Elasticsearch for further analysis and security testing."
weight = 1
sort_by = "weight"

[extra]
+++

The "Deliver" feature in Noir is a powerful way to integrate your code analysis with other tools in your security workflow. Instead of just viewing the results in your terminal, you can send the discovered endpoints directly to proxy tools like Burp Suite or ZAP, or to a data analysis platform like Elasticsearch.

This makes it much easier to move from code analysis to active security testing or to store and analyze your findings over time.

## How to Use the Deliver Feature

The Deliver feature is controlled by a set of command-line flags:

*   `--send-req`: Send the results as a web request.
*   `--send-proxy http://proxy...`: Send the results through an HTTP proxy.
*   `--send-es http://es...`: Send the results to an Elasticsearch instance.
*   `--with-headers X-Header:Value`: Add custom headers to the requests.
*   `--use-matchers string`: Only send endpoints that match a specific pattern (URL, method, or method:URL combination).
*   `--use-filters string`: Exclude endpoints that match a specific pattern (URL, method, or method:URL combination).

### Sending to a Proxy

To send all discovered endpoints to a proxy like Burp Suite or ZAP running on `http://localhost:8080`, you would use the `--send-proxy` flag:

```bash
noir -b ./source --send-proxy http://localhost:8080
```

This will populate your proxy's history with all the endpoints found by Noir, so you can immediately start testing them.

![](./deliver-proxy.png)

### Adding Custom Headers

You can also add custom headers to the requests that Noir sends. This is useful if you need to include an authentication token or other specific headers.

```bash
noir -b ./source --send-proxy http://localhost:8080 --with-headers "Authorization: Bearer your-token"
```

![](./deliver-header.png)

### Filtering and Matching

If you only want to send a subset of the discovered endpoints, you can use the `--use-matchers` and `--use-filters` flags. The filtering supports several patterns:

#### URL-based Filtering (Backward Compatible)
To only send endpoints that contain the word "api" in their URL:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-matchers "api"
```

#### Method-based Filtering
To only send GET requests:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-matchers "GET"
```

To exclude all POST requests:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-filters "POST"
```

#### Method and URL Combination
To only send POST requests to API endpoints:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-matchers "POST:/api"
```

To exclude GET requests to admin pages:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-filters "GET:/admin"
```

#### Supported HTTP Methods
The method-based filtering supports all standard HTTP methods: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, TRACE, CONNECT (case insensitive).

#### Multiple Patterns
You can use multiple matchers or filters:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-matchers "GET" --use-matchers "POST:/api"
```

![](./deliver-mf.png)

By using the Deliver feature, you can create a seamless workflow between code analysis and security testing, saving you time and effort.
