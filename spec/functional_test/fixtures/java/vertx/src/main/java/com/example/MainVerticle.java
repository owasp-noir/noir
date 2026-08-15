package com.example;

import io.vertx.core.Vertx;
import io.vertx.core.http.HttpMethod;
import io.vertx.core.http.HttpServer;
import io.vertx.ext.web.Router;
import io.vertx.ext.web.RoutingContext;
import io.vertx.ext.web.handler.BodyHandler;
import io.vertx.ext.web.handler.StaticHandler;

public class MainVerticle {
  private static final String API_PREFIX = "/api";
  private static final String REPORTS = "/reports";
  private static final String ADMIN_PREFIX = "/admin";
  private static final String TASKS = "/tasks";
  
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
    router.route(HttpMethod.POST, "/imports/:importId").handler(this::importData);
    router.get(API_PREFIX + REPORTS + "/:reportId").handler(this::getReport);
    router.route(API_PREFIX + "/exports/:exportId").get(this::exportData);
    router.route(HttpMethod.DELETE, API_PREFIX + "/imports/:importId").handler(this::deleteImport);
    router.route().method(HttpMethod.GET).path(API_PREFIX + TASKS + "/:taskId").handler(this::getTask);
    router.route().path("/jobs/:jobId").method(HttpMethod.POST).handler(this::createJob);
    router.route(API_PREFIX + "/any/:anyId").handler(this::handleAny);

    // HTTP QUERY routes (RFC 10008)
    router.query("/search").handler(ctx -> {
      String q = ctx.queryParam("q");
      ctx.response().end("Search: " + q);
    });
    router.route(HttpMethod.QUERY, "/search/items").handler(this::searchItems);
    router.route("/advanced-search").method(HttpMethod.QUERY).handler(this::advancedSearch);
    router.route("/multi-search").method(HttpMethod.GET).method(HttpMethod.QUERY).handler(this::multiSearch);
    
    // Sub-router mounting
    Router apiRouter = Router.router(vertx);
    apiRouter.get("/v1/items").handler(this::getItems);
    apiRouter.post("/v1/items").handler(this::createItem);
    apiRouter.query("/v1/search").handler(this::apiSearch);
    router.mountSubRouter("/api", apiRouter);

    Router adminRouter = Router.router(vertx);
    adminRouter.get("/metrics/:metricId").handler(this::getMetric);
    router.mountSubRouter(ADMIN_PREFIX, adminRouter);

    Router eventBusBridge = Router.router(vertx);
    router.route("/eventbus/*").subRouter(eventBusBridge);
    
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

  private void importData(RoutingContext ctx) {
    String importId = ctx.request().getParam("importId");
    ctx.response().end("Import " + importId);
  }

  private void deleteImport(RoutingContext ctx) {
    String importId = ctx.request().getParam("importId");
    ctx.response().end("Import " + importId + " deleted");
  }

  private void getReport(RoutingContext ctx) {
    String reportId = ctx.request().getParam("reportId");
    ctx.response().end("Report " + reportId);
  }

  private void exportData(RoutingContext ctx) {
    String exportId = ctx.request().getParam("exportId");
    ctx.response().end("Export " + exportId);
  }
  
  private void getItems(RoutingContext ctx) {
    ctx.response().end("Items list");
  }
  
  private void createItem(RoutingContext ctx) {
    ctx.response().end("Item created");
  }

  private void getMetric(RoutingContext ctx) {
    String metricId = ctx.request().getParam("metricId");
    ctx.response().end("Metric " + metricId);
  }

  private void getTask(RoutingContext ctx) {
    String taskId = ctx.request().getParam("taskId");
    ctx.response().end("Task " + taskId);
  }

  private void createJob(RoutingContext ctx) {
    String jobId = ctx.request().getParam("jobId");
    ctx.response().end("Job " + jobId);
  }

  private void handleAny(RoutingContext ctx) {
    String anyId = ctx.request().getParam("anyId");
    ctx.response().end("Any method " + anyId);
  }

  private void searchItems(RoutingContext ctx) {
    String filter = ctx.queryParam("filter");
    ctx.response().end("Items search " + filter);
  }

  private void advancedSearch(RoutingContext ctx) {
    String query = ctx.queryParam("query");
    ctx.response().end("Advanced search " + query);
  }

  private void multiSearch(RoutingContext ctx) {
    String term = ctx.queryParam("term");
    ctx.response().end("Multi search " + term);
  }

  private void apiSearch(RoutingContext ctx) {
    String keyword = ctx.queryParam("keyword");
    ctx.response().end("API search " + keyword);
  }

  // SQL-client calls share the `query` spelling with Router but must not
  // surface as QUERY routes.
  private void loadUsers(SqlClient client, Pool pool) {
    client.query("SELECT * FROM users").execute();
    pool.query("UPDATE users SET active = true").execute();
  }
}
