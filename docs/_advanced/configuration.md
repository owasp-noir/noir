---
title: Configuration
has_children: false
nav_order: 1
permalink: /configuration
layout: page
---

# Configuration
{: .d-inline-block }

Since (v0.16.0) 
{: .label .label-green }

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

# Config values are defaults; CLI options take precedence.
# **************************************************************

# Base directory for the application
base: ""

# Whether to use color in the output
color: "true"

# The configuration file to use
config_file: ""

# The number of concurrent operations to perform
concurrency: "100"

# Whether to enable debug mode
debug: "false"

# Technologies to exclude
exclude_techs: ""

# The format to use for the output
format: "plain"

# Whether to display HTTP status codes in the output
status_codes: "false"

# Whether to exclude HTTP status codes from the output
exclude_codes: ""

# Whether to include the path in the output
include_path: "false"

# Whether to disable logging
nolog: "false"

# The output file to write to
output: ""

# The Elasticsearch server to send data to
# e.g http://localhost:9200
send_es: ""

# The proxy server to use
# e.g http://localhost:8080
send_proxy: ""

# Whether to send a request
send_req: "false"

# Whether to send headers with the request (Array of strings)
# e.g "Authorization: Bearer token"
send_with_headers:

# The value to set for pvalue (Array of strings)
set_pvalue:
set_pvalue_header:
set_pvalue_cookie:
set_pvalue_query:
set_pvalue_form:
set_pvalue_json:
set_pvalue_path:

# The technologies to use
techs: ""

# The URL to use
url: ""

# Whether to use filters (Array of strings)
use_filters:

# Whether to use matchers (Array of strings)
use_matchers:

# Whether to use all taggers
all_taggers: "false"

# The taggers to use
# e.g "tagger1,tagger2"
# To see the list of all taggers, please use the noir command with --list-taggers
use_taggers: ""

# The diff file to use
diff: ""
```