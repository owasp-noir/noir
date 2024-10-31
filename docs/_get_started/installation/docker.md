---
title: Docker (GHCR)
has_children: false
parent: Installation
nav_order: 4
toc: true
layout: page
---

Docker is a popular containerization platform that simplifies the deployment and management of applications by packaging them into containers. The GitHub Container Registry (GHCR) allows you to store and manage Docker container images within GitHub.

```bash
docker pull ghcr.io/owasp-noir/noir:latest
```

To reference this Docker image in your own Dockerfile, you can use the following FROM statement:

```dockerfile
FROM ghcr.io/owasp-noir/noir:latest
```

or Replace `<version>` with the specific version tag you need.

```dockerfile
FROM ghcr.io/owasp-noir/noir:<version>
```

If you want to see packages by Docker tag, visit [this page](https://github.com/owasp-noir/noir/pkgs/container/noir).