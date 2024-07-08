---
title: Use Deliver
has_children: false
nav_order: 5
layout: page
---

{% include toc.md %}

## Usage

```bash
noir -b <BASE_PATH> --send-proxy <PROXY_URL>

#  DELIVER:
#    --send-req                       Send results to a web request
#    --send-proxy http://proxy..      Send results to a web request via an HTTP proxy
#    --send-es http://es..            Send results to Elasticsearch
#    --with-headers X-Header:Value    Add custom headers to be included in the delivery
#    --use-matchers string            Send URLs that match specific conditions to the Deliver
#    --use-filters string             Exclude URLs that match specified conditions and send the rest to Deliver
```