package com.example;

import org.apache.camel.builder.RouteBuilder;

public class UserRoutes extends RouteBuilder {
  @Override
  public void configure() {
    restConfiguration().component("servlet");
    rest("/users").get("/{id}").to("direct:user");
    from("servlet:/hello").to("direct:hello");
  }
}
