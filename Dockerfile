##= BUILDER =##
FROM crystallang/crystal:1.19.0-alpine AS builder
WORKDIR /noir
COPY . .

RUN apk add --no-cache yaml-dev zstd-dev && \
    shards install --production && \
    shards build --release --no-debug --production --static
# Ref: https://crystal-lang.org/reference/1.15/guides/static_linking.html

##= RUNNER =##
FROM debian:13-slim
LABEL org.opencontainers.image.title="OWASP Noir"
LABEL org.opencontainers.image.version="0.29.1"
LABEL org.opencontainers.image.description="Hunt every Endpoint in your code, expose Shadow APIs, map the Attack Surface."
LABEL org.opencontainers.image.authors="Noir Team (@hahwul, @ksg97031)"
LABEL org.opencontainers.image.source=https://github.com/owasp-noir/noir
LABEL org.opencontainers.image.documentation="https://owasp-noir.github.io/noir/"
LABEL org.opencontainers.image.licenses=MIT

COPY --from=builder /noir/bin/noir /usr/local/bin/noir

CMD ["noir"]
