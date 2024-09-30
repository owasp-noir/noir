---
title: Passive Scan Rule
parent: Passive Scan
has_children: false
nav_order: 1
layout: page
---

```yaml
id: hahwul-test
info:
  name: use x-api-key
  author: 
    - abcd
    - aaaa
  severity: critical
  description: ....
  reference:
    - https://google.com

matchers-condition: and
matchers:
  - type: word
    patterns:
      - api
    condition: or

  - type: regex
    patterns:
      - ".*"
      - "^a"
    condition: or

category: secret
techs:
  - '*'
  - ruby-rails
```