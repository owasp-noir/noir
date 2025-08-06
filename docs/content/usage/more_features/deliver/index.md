+++
title = "Deliver"
description = "Guide to configuring Noir using config.yaml files with predefined settings and preferences"
weight = 1
sort_by = "weight"

[extra]
+++

Deliver is a feature designed to transmit Endpoints discovered by Noir to other tools. Unlike Pipelines that use Output, it can forward information to proxy tools such as Caido, ZAP, and Burp, as well as to ElasticSearch. This functionality allows for easier security testing and simplifies finding and utilizing service Endpoints in a DevOps Pipeline.

```bash
#  DELIVER:
#    --send-req                       Send results to a web request
#    --send-proxy http://proxy..      Send results to a web request via an HTTP proxy
#    --send-es http://es..            Send results to Elasticsearch
#    --with-headers X-Header:Value    Add custom headers to be included in the delivery
#    --use-matchers string            Send URLs that match specific conditions to the Deliver
#    --use-filters string             Exclude URLs that match specified conditions and send the rest to Deliver
```

## Detailed Features of Devlier

### Send Results to a Web Request

Option: `--send-req`
Description: This option enables you to send results directly to a web request. It is useful for integrating with various web services and APIs that accept HTTP requests.


### Send Results via an HTTP Proxy

Option: `--send-proxy http://proxy..`
Description: With this option, you can send results to a web request through an HTTP proxy. This is beneficial when you need to route your requests through a proxy server for reasons such as network restrictions or logging.

![](./deliver-proxy.png)

### Send Results to Elasticsearch

Option: `--send-es http://es..`
Description: This option allows you to send results directly to an Elasticsearch instance. It's particularly useful for storing and analyzing large volumes of endpoint data, providing powerful search and analytics capabilities.

### Include Custom Headers in Delivery Requests

Option: `--with-headers X-Header:Value`
Description: This feature lets you add custom headers to your delivery requests. It is beneficial for scenarios requiring specific headers for authentication or to comply with API requirements.

```bash
noir -b ./source --send-proxy http://localhost:8090 --with-headers "X-API-Key: ABCD"
```

![](./deliver-header.png)

### Filter and Match Specific URLs

Options: `--use-matchers string` and `--use-filters string`
Description: These options enable you to send URLs that match specific conditions and exclude URLs that meet certain criteria. This allows for more targeted and efficient endpoint management by focusing on relevant URLs and filtering out unwanted ones.

![](./deliver-mf.png)
