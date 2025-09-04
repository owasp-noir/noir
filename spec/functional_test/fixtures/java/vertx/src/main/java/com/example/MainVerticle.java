package com.example;

import io.vertx.core.Vertx;
import io.vertx.core.http.HttpServer;
import io.vertx.ext.web.Router;
import io.vertx.ext.web.RoutingContext;
import io.vertx.ext.web.handler.BodyHandler;
import io.vertx.ext.web.handler.StaticHandler;

public class MainVerticle {
  
  public static void main(String[] args) {
    Vertx vertx = Vertx.vertx();
    HttpServer server = vertx.createHttpServer();
    
    Router router = Router.router(vertx);
    
    // Basic routes
    router.get("/").handler(this::indexHandler);
    router.get("/health").handler(this::healthCheck);
    router.post("/api/users").handler(this::createUser);
    router.put("/api/users/:id").handler(this::updateUser);
    router.delete("/api/users/:id").handler(this::deleteUser);
    router.patch("/api/users/:id").handler(this::patchUser);
    router.head("/api/status").handler(this::statusHead);
    router.options("/api/options").handler(this::optionsHandler);
    
    // Route with handler chain
    router.route("/api/*").handler(BodyHandler.create());
    router.get("/api/products/:category").handler(this::getProductsByCategory);
    
    // Alternative syntax using route() then method()
    router.route("/orders/:id").get(this::getOrder);
    router.route("/orders").post(this::createOrder);
    router.route("/orders/:id").put(this::updateOrder);
    
    // Sub-router mounting
    Router apiRouter = Router.router(vertx);
    apiRouter.get("/v1/items").handler(this::getItems);
    apiRouter.post("/v1/items").handler(this::createItem);
    router.mountSubRouter("/api", apiRouter);
    
    // Static resources
    router.route("/static/*").handler(StaticHandler.create());
    
    server.requestHandler(router).listen(8080);
  }
  
  private void indexHandler(RoutingContext ctx) {
    ctx.response().end("Hello Vert.x!");
  }
  
  private void healthCheck(RoutingContext ctx) {
    ctx.response().end("OK");
  }
  
  private void createUser(RoutingContext ctx) {
    ctx.response().end("User created");
  }
  
  private void updateUser(RoutingContext ctx) {
    String userId = ctx.request().getParam("id");
    ctx.response().end("User " + userId + " updated");
  }
  
  private void deleteUser(RoutingContext ctx) {
    String userId = ctx.request().getParam("id");
    ctx.response().end("User " + userId + " deleted");
  }
  
  private void patchUser(RoutingContext ctx) {
    String userId = ctx.request().getParam("id");
    ctx.response().end("User " + userId + " patched");
  }
  
  private void statusHead(RoutingContext ctx) {
    ctx.response().end();
  }
  
  private void optionsHandler(RoutingContext ctx) {
    ctx.response().putHeader("Allow", "GET,POST,PUT,DELETE,OPTIONS").end();
  }
  
  private void getProductsByCategory(RoutingContext ctx) {
    String category = ctx.request().getParam("category");
    ctx.response().end("Products in category: " + category);
  }
  
  private void getOrder(RoutingContext ctx) {
    String orderId = ctx.request().getParam("id");
    ctx.response().end("Order: " + orderId);
  }
  
  private void createOrder(RoutingContext ctx) {
    ctx.response().end("Order created");
  }
  
  private void updateOrder(RoutingContext ctx) {
    String orderId = ctx.request().getParam("id");
    ctx.response().end("Order " + orderId + " updated");
  }
  
  private void getItems(RoutingContext ctx) {
    ctx.response().end("Items list");
  }
  
  private void createItem(RoutingContext ctx) {
    ctx.response().end("Item created");
  }
}