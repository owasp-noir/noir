---
title: Configuration
weight: 1
description: "Guide to configuring Noir using config.yaml files with predefined settings and preferences"
---

Configuration allows you to predefine various flags for Noir, making it easier to manage and use the tool with your preferred settings.

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
color: true

# The configuration file to use
config_file: ""

# The number of concurrent operations to perform
concurrency: "50"

# Whether to enable debug mode
debug: false

# Whether to enable verbose mode
verbose: false

# The status codes to exclude
exclude_codes: ""

# Technologies to exclude
exclude_techs: ""

# The format to use for the output
format: "plain"

# Whether to include the path in the output
include_path: false

# Whether to disable logging
nolog: false

# The output file to write to
output: ""

# The Elasticsearch server to send data to
# e.g http://localhost:9200
send_es: ""

# The proxy server to use
# e.g http://localhost:8080
send_proxy: ""

# Whether to send a request
send_req: false

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

# The status codes to use
status_codes: false

# The technologies to use
techs: ""

# The URL to use
url: ""

# Whether to use filters (Array of strings)
use_filters:

# Whether to use matchers (Array of strings)
use_matchers:

# Whether to use all taggers
all_taggers: false

# The taggers to use
# e.g "tagger1,tagger2"
# To see the list of all taggers, please use the noir command with --list-taggers
use_taggers: ""

# The diff file to use
diff: ""

# The passive rules to use
# e.g /path/to/rules
passive_scan: false
passive_scan_path: []

# The AI server URL
ai_provider: ""

# The AI model to use
ai_model: ""

# The API key for the AI server
ai_key: ""
````