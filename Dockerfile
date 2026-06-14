##= BUILDER =##
FROM crystallang/crystal:1.20.2-alpine AS builder
WORKDIR /noir
COPY . .

RUN apk add --no-cache yaml-dev zstd-dev git && \
    shards install --production && \
    shards build --release --no-debug --production --static
# Ref: https://crystal-lang.org/reference/1.15/guides/static_linking.html

# Snapshot the passive-rules repo so the runner stage can ship them
# pre-baked at `/opt/noir/passive_rules`. `--depth=1` keeps the
# tarball-sized clone tiny, then we drop `.git` so the runtime image
# doesn't carry repo metadata it can't use (no git binary downstream).
RUN git clone --depth=1 https://github.com/owasp-noir/noir-passive-rules.git /noir-passive-rules && \
    rm -rf /noir-passive-rules/.git

##= RUNNER =##
FROM debian:13-slim

# Standard OCI labels
LABEL org.opencontainers.image.title="OWASP Noir"
LABEL org.opencontainers.image.version="1.1.0"
LABEL org.opencontainers.image.description="Hunt every Endpoint in your code, expose Shadow APIs, map the Attack Surface."
LABEL org.opencontainers.image.authors="Noir Team (@hahwul, @ksg97031)"
LABEL org.opencontainers.image.source=https://github.com/owasp-noir/noir
LABEL org.opencontainers.image.documentation="https://owasp-noir.github.io/noir/"
LABEL org.opencontainers.image.licenses=MIT

# GitHub Action labels — the published image doubles as the action
# runtime so `action.yml` can `docker run` it directly instead of
# building a sibling Dockerfile on every workflow invocation.
LABEL "com.github.actions.name"="OWASP Noir Action"
LABEL "com.github.actions.description"="Hunt every Endpoint in your code, expose Shadow APIs, map the Attack Surface."
LABEL "com.github.actions.icon"="search"
LABEL "com.github.actions.color"="purple"

# Runtime deps:
#   * jq — entrypoint.sh parses noir's JSON output to populate the
#     `endpoints` / `passive_results` action outputs.
#   * ca-certificates — needed when noir or downstream tooling needs to
#     hit HTTPS endpoints from inside the container.
RUN apt-get update && \
    apt-get install -y --no-install-recommends jq ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /noir/bin/noir /usr/local/bin/noir
COPY --chmod=755 github-action/entrypoint.sh /entrypoint.sh
# Image-baked default ruleset. `noir scan -P` resolves to this when the
# user's $NOIR_HOME/passive_rules tree is empty — see
# PassiveRulesUpdater.effective_rules_path. Users who want fresh rules
# can still pull the upstream repo into their config dir or pass
# `--passive-scan-path`.
COPY --from=builder /noir-passive-rules /opt/noir/passive_rules

# Default to `noir` so `docker run ghcr.io/owasp-noir/noir` keeps the
# CLI-as-usual behaviour. The GitHub Action composite invokes
# `docker run … /entrypoint.sh` explicitly so the action path doesn't
# rely on the ENTRYPOINT here.
CMD ["noir"]
