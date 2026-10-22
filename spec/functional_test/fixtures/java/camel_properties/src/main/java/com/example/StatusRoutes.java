package com.example;

import org.apache.camel.builder.RouteBuilder;

public class StatusRoutes extends RouteBuilder {
  @Override
  public void configure() {
    rest("/v1").get("/status").to("direct:status");
    from("platform-http:/raw").to("direct:raw");
  }
}
