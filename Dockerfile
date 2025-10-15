##= BUILDER =##
FROM 84codes/crystal:latest-debian-13 As builder

WORKDIR /noir
COPY . .

RUN apt-get update && \
    apt-get install -y libyaml-dev zlib1g-dev libzstd-dev pkg-config && \
    shards install --production && \
    crystal build -o bin/noir src/noir.cr --release --no-debug --static --link-flags "-Wl,--start-group -lssl -lcrypto -lz -lzstd -Wl,--end-group"
# Ref: https://crystal-lang.org/reference/1.15/guides/static_linking.html

##= RUNNER =##
FROM debian:13-slim
LABEL org.opencontainers.image.title="OWASP Noir"
LABEL org.opencontainers.image.version="0.24.0"
LABEL org.opencontainers.image.description="OWASP Noir is an open-source project specializing in identifying attack surfaces for enhanced whitebox security testing and security pipeline."
LABEL org.opencontainers.image.authors="Noir Team (@hahwul, @ksg97031)"
LABEL org.opencontainers.image.source=https://github.com/owasp-noir/noir
LABEL org.opencontainers.image.documentation="https://owasp-noir.github.io/noir/"
LABEL org.opencontainers.image.licenses=MIT

COPY --from=builder /noir/bin/noir /usr/local/bin/noir
#COPY --from=builder /etc/ssl/cert.pem /etc/ssl/

CMD ["noir"]
