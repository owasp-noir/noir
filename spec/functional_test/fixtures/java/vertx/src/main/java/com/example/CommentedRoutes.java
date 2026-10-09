package com.example;

import io.vertx.ext.web.Router;

// Commented-out routes are not routes, and an apostrophe in a comment must
// not open a char literal that swallows the next handler.
public class CommentedRoutes {
  public void mount(Router router) {
    // router.get("/commented").handler(this::old);
    /*
    router.post("/block-commented").handler(this::old);
    */
    router.route("/apostrophe").handler(ctx -> {
      // don't forget auth
      ctx.response().end("ok");
    });
  }
}
