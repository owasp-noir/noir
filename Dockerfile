FROM crystallang/crystal:latest-alpine As builder

WORKDIR /noir
COPY . .

RUN shards install
RUN shards build --release --no-debug

CMD ["/noir/bin/noir"]