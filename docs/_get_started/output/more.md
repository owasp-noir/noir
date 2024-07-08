---
title: More
parent: Output Formatting
has_children: false
nav_order: 4
layout: page
---

## httpie

```bash
noir -b . -f httpie -u https://www.hahwul.com

# http GET https://www.hahwul.com/ "x-api-key: "
# http POST https://www.hahwul.com/query "query=" "Cookie: my_auth="
# http GET https://www.hahwul.com/token "client_id=&redirect_url=&grant_type="
# http GET https://www.hahwul.com/socket
# http GET https://www.hahwul.com/1.html
# http GET https://www.hahwul.com/2.html
```

## Only-x
```bash
noir -b . -f only-url
# ...
# /
# /query
# /token
# /socket
# /1.html
# /2.html
```