package com.example;

import org.apache.camel.builder.RouteBuilder;

public class ItemRoutes extends RouteBuilder {
  @Override
  public void configure() {
    rest("/items").get().to("direct:items");
  }
}
