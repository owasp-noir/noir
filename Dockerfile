FROM crystallang/crystal:latest-alpine As builder

WORKDIR /noir
COPY . .

RUN shards install
RUN shards build --release --no-debug
RUN cp /noir/bin/noir /usr/local/bin/noir

CMD ["noir"]