---
title: Build
has_children: false
parent: Installation
nav_order: 3
toc: true
layout: page
---

# Build Noir

You can build and use Noir directly by following the steps below.

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
