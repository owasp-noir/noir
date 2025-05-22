##= BUILDER =##
FROM 84codes/crystal:latest-debian-12 As builder

WORKDIR /noir
COPY . .

RUN apt-get update && \
    apt-get install -y libyaml-dev && \
    shards install --production && \
    shards build --release --no-debug --production --static
# Ref: https://crystal-lang.org/reference/1.15/guides/static_linking.html

##= RUNNER =##
FROM debian:12-slim
LABEL org.opencontainers.image.title="OWASP Noir"
LABEL org.opencontainers.image.version="0.21.1"
LABEL org.opencontainers.image.description="OWASP Noir is an open-source project specializing in identifying attack surfaces for enhanced whitebox security testing and security pipeline."
LABEL org.opencontainers.image.authors="Noir Team (@hahwul, @ksg97031)"
LABEL org.opencontainers.image.source=https://github.com/owasp-noir/noir
LABEL org.opencontainers.image.documentation="https://owasp-noir.github.io/noir/"
LABEL org.opencontainers.image.licenses=MIT

COPY --from=builder /noir/bin/noir /usr/local/bin/noir
#COPY --from=builder /etc/ssl/cert.pem /etc/ssl/

USER 2:2

CMD ["noir"]
