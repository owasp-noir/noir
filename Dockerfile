# BUILDER
FROM crystallang/crystal:latest-alpine As builder

WORKDIR /noir
COPY . .

RUN shards install --production
RUN shards build --release --production --static --no-debug

# RUNNER
FROM alpine
USER 2:2

COPY --from=builder /noir/bin/noir /usr/local/bin/noir
COPY --from=builder /etc/ssl/cert.pem /etc/ssl/

CMD ["noir"]
