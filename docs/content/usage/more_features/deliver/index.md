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
*   `--use-matchers string`: Only send URLs that match a specific pattern.
*   `--use-filters string`: Exclude URLs that match a specific pattern.

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

If you only want to send a subset of the discovered endpoints, you can use the `--use-matchers` and `--use-filters` flags. For example, to only send endpoints that contain the word "api", you could use:

```bash
noir -b ./source --send-proxy http://localhost:8080 --use-matchers "api"
```

![](./deliver-mf.png)

By using the Deliver feature, you can create a seamless workflow between code analysis and security testing, saving you time and effort.
