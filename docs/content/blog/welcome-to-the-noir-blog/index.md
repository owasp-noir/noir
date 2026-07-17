+++
title = "Welcome to the Noir blog"
description = "A new space for release deep dives, performance notes, design rationale, and the writing that doesn't fit in a changelog."
date = "2026-05-17"
tags = ["meta", "announcements"]
authors = ["hahwul"]
template = "blog_post"
+++

Hi, this is hahwul. I've been writing Noir tips and notes on my personal blog for a while, but it felt better to have an official channel for it, so we're opening a blog space inside the project docs.

It's a small experimental section sitting alongside the documentation, meant to collect the kinds of writing that don't quite fit into release notes or reference pages. Better here than scattered across PR descriptions.

## What you'll find here

- **Release deep dives**: what landed in recent versions, the background, and the trade-offs we picked.
- **Performance and accuracy investigations**: when a benchmark or a false-positive sweep turns up something worth writing about, we'll post it.
- **Framework coverage notes**: the parsing edge cases we run into while adding support for a new Rust/Python/JVM framework.
- **Design rationale**: why the analyzer pipeline, optimizer passes, and AI context ended up shaped the way they are.
- **Tips**: practical know-how for getting more out of Noir in everyday use.

## How it fits the rest of the docs

- The [Get Started](@/get_started/_index.md) guide stays the canonical place to learn the tool.
- The [Usage](@/usage/_index.md) section keeps reference material: flags, supported frameworks, output formats.
- The blog supplements both with narrative content. If a topic graduates into something every user should know, it migrates into the docs.

## Cadence

There's no schedule. Posts go up when there's something to write about. For regular updates, follow the GitHub [releases](https://github.com/owasp-noir/noir/releases); check back here once in a while for the longer reads.

If you'd like to contribute a post (write about how you use Noir, share a CI integration, or unpack a framework's routing model), open a PR with a draft. Authors get a card next to the post.
