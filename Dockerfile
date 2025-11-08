##= BUILDER =##
FROM 84codes/crystal:latest-debian-13 AS builder
WORKDIR /noir
COPY . .

RUN apt-get update && \
    apt-get install -y libyaml-dev libzstd-dev zlib1g-dev pkg-config && \
    mv /usr/bin/pkg-config /usr/bin/pkg-config-original && \
    echo '#!/bin/sh' > /usr/bin/pkg-config && \
    echo 'if echo "$@" | grep -q -- "--libs"; then' >> /usr/bin/pkg-config && \
    echo '  exec /usr/bin/pkg-config-original "$@" --static' >> /usr/bin/pkg-config && \
    echo 'else' >> /usr/bin/pkg-config && \
    echo '  exec /usr/bin/pkg-config-original "$@"' >> /usr/bin/pkg-config && \
    echo 'fi' >> /usr/bin/pkg-config && \
    chmod +x /usr/bin/pkg-config && \
    shards install --production && \
    shards build --release --no-debug --production --static
# Ref: https://crystal-lang.org/reference/1.15/guides/static_linking.html

##= RUNNER =##
FROM debian:13-slim
LABEL org.opencontainers.image.title="OWASP Noir"
LABEL org.opencontainers.image.version="0.25.0"
LABEL org.opencontainers.image.description="OWASP Noir is an open-source project specializing in identifying attack surfaces for enhanced whitebox security testing and security pipeline."
LABEL org.opencontainers.image.authors="Noir Team (@hahwul, @ksg97031)"
LABEL org.opencontainers.image.source=https://github.com/owasp-noir/noir
LABEL org.opencontainers.image.documentation="https://owasp-noir.github.io/noir/"
LABEL org.opencontainers.image.licenses=MIT

COPY --from=builder /noir/bin/noir /usr/local/bin/noir
#COPY --from=builder /etc/ssl/cert.pem /etc/ssl/

CMD ["noir"]
