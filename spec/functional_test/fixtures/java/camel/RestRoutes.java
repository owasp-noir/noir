package com.example;

import org.apache.camel.builder.RouteBuilder;
import org.apache.camel.model.rest.RestParamType;

public class RestRoutes extends RouteBuilder {
  private static final String ORDERS = "/orders";

  @Override public void configure() {
    restConfiguration().component("servlet").contextPath("/api");
    rest(/* base */ "/users")
      .get("/{id}").to("direct:getUser")
      .post().type(User.class).to("direct:createUser")
      .delete("/{id}").to("direct:deleteUser");
    from("platform-http:/hello?httpMethodRestrict=GET").setBody(constant("hi"));

    rest(ORDERS)
      .get()
        .param().name(/* query */ "status").type(RestParamType.query).endParam()
        .to("direct:listOrders")
      .put("/{id}")
        .param().name("X-Token").type(RestParamType.header).endParam()
        .type(Order.class)
        .to("direct:updateOrder");

    rest("/a").patch("/p").to("direct:1")
      .head("/h").to("direct:2")
      .verb("options", "/o")
        .param().name("depth").type(RestParamType.query).endParam()
        .to("direct:3")
      .verb("patch").to("direct:4");

    from("rest:get:ping").to("direct:ping");
    from("jetty:http://0.0.0.0:8080/legacy").to("direct:legacy");
    from("servlet:/upload?httpMethodRestrict=POST,PUT").to("direct:upload");

    // Not HTTP consumers: no endpoints.
    from("direct:getUser").to("bean:userService?method=get");
    from("timer:tick?period=1000").log("tick");
    // rest("/commented").get("/out");
    // Unresolvable base: dropped rather than reported as /api/skip.
    rest(Paths.EXTERNAL).get("/skip").to("direct:skip");
  }
}
