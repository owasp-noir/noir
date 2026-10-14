package com.example;

import io.vertx.core.AbstractVerticle;
import io.vertx.ext.web.Router;

// Vert.x 4 sub-router mount: child routes live under the wildcard prefix.
public class SubRouterVerticle extends AbstractVerticle {
  @Override
  public void start() {
    Router router = Router.router(vertx);
    Router backoffice = Router.router(vertx);
    backoffice.get("/status").handler(ctx -> ctx.end("ok"));
    backoffice.delete("/sessions/:sessionId").handler(ctx -> ctx.end());
    router.route("/backoffice/*").subRouter(backoffice);
    vertx.createHttpServer().requestHandler(router).listen(8081);
  }
}
