package com.example;

import io.vertx.core.Vertx;
import io.vertx.ext.web.Router;
import io.vertx.ext.web.RoutingContext;

public class MainVerticle {
  private final UserService service = new UserService();

  public void start() {
    Vertx vertx = Vertx.vertx();
    Router router = Router.router(vertx);

    router.post("/users/:id").handler(this::createUser);
    router.route("/orders/:id").get(this::getOrder);
  }

  private void createUser(RoutingContext ctx) {
    String id = ctx.pathParam("id");
    User user = parseUser(ctx);
    service.save(user, id);
    AuditLog.write("create");
    ctx.response().end("ok");
  }

  private void getOrder(RoutingContext ctx) {
    String id = ctx.pathParam("id");
    Order order = findOrder(id);
    AuditLog.write("get");
    ctx.response().end(order.id);
  }

  private User parseUser(RoutingContext ctx) {
    return new User();
  }

  private Order findOrder(String id) {
    return new Order(id);
  }
}

class User {
}

class Order {
  String id;

  Order(String id) {
    this.id = id;
  }
}

class UserService {
  void save(User user, String id) {
  }
}

class AuditLog {
  static void write(String event) {
  }
}
