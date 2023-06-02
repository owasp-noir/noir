# BUILDER
FROM crystallang/crystal:latest-alpine As builder

WORKDIR /noir
COPY . .

RUN shards install
RUN shards build --release --no-debug

# RUNNER
FROM crystallang/crystal:latest-alpine As runner
COPY --from=builder /noir/bin/noir /usr/local/bin/noir
CMD ["noir"]