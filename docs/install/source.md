---
title: From source
parent: Installation
has_children: false
nav_order: 3
layout: page
---

## Install Crystal-lang

> [https://crystal-lang.org/install/](https://crystal-lang.org/install/)

## Clone this repo
```bash
git clone https://github.com/owasp-noir/noir
cd noir
```

## Build
```bash
# Install Dependencies
shards install

# Build
shards build --release --no-debug

# Copy binary
cp ./bin/noir /usr/bin/
```