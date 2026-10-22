package com.example;

import io.vertx.core.Vertx;
import io.vertx.ext.web.Router;

public class MainVerticle {
  public void start() {
    Vertx vertx = Vertx.vertx();
    Router router = Router.router(vertx);

    router.get("/real").handler(ctx -> ctx.response().end("ok"));
  }
}
