---
title: Configuration
has_children: false
nav_order: 1
permalink: /configuration
layout: page
---

{% include toc.md %}

## Config Home Path

| OS | Path |
|---|---|
| MacOS: | `~/.config/noir` |
| Linux: | `~/.config/noir` |
| Windows: | `%APPDATA%\noir` |

## Config YAML (config.yaml)

`$CONFIG_HOME/config.yaml` 

```yaml
---
# Noir configuration file
# This file is used to store the configuration options for Noir.
# You can edit this file to change the configuration options.
# **************************************************************

# Base directory for the application
base: ""

# Whether to use color in the output
color: "yes"

# The configuration file to use
config_file: ""

# The number of concurrent operations to perform
concurrency: "100"

# Whether to enable debug mode
debug: "no"

# Technologies to exclude
exclude_techs: ""

# The format to use for the output
format: "plain"

# Whether to include the path in the output
include_path: "no"

# Whether to disable logging
nolog: "no"

# The output file to write to
output: ""

# The Elasticsearch server to send data to
send_es: ""

# The proxy server to use
send_proxy: ""

# Whether to send a request
send_req: "no"

# Whether to send headers with the request
send_with_headers: ""

# The value to set for pvalue
set_pvalue: ""

# The technologies to use
techs: ""

# The URL to use
url: ""

# Whether to use filters
use_filters: ""

# Whether to use matchers
use_matchers: ""

# Whether to use all taggers
all_taggers: "no"

# The taggers to use
use_taggers: ""

# The diff file to use
diff: ""
```