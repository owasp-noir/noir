require "../../func_spec.cr"

extected_endpoints = [
  # MyRoutingConfiguration.java
  Endpoint.new("/{user}", "GET", [Param.new("user", "", "path")]),
  Endpoint.new("/{user}/customers", "GET", [Param.new("user", "", "path")]),
  Endpoint.new("/{user}/0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_.~", "GET", [Param.new("user", "", "path")]),
  Endpoint.new("/{user}", "DELETE", [Param.new("user", "", "path")]),
  Endpoint.new("/{user}", "POST", [Param.new("user", "", "path")]),
  Endpoint.new("/{user}", "PUT", [Param.new("user", "", "path")]),
  # QuoteRouter.java
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/echo", "POST"),
  Endpoint.new("/quotes", "GET"),
  Endpoint.new("/quotes/0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_.~", "GET"),
  # ItemController.java
  Endpoint.new("/items/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/items/json/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/items/", "POST", [Param.new("id", "", "form"), Param.new("name", "", "form")]),
  Endpoint.new("/items/update/{id}", "PUT", [Param.new("id", "", "path"), Param.new("id", "", "json"), Param.new("name", "", "json")]),
  Endpoint.new("/items/delete/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/items/requestmap/put", "PUT"),
  Endpoint.new("/items/requestmap/delete", "DELETE"),
  Endpoint.new("/items/multiple/methods", "GET"),
  Endpoint.new("/items/multiple/methods", "POST"),
  Endpoint.new("/items/multiple/methods2", "GET"),
  Endpoint.new("/items/multiple/methods2", "POST"),
  Endpoint.new("/greet", "GET", [
    Param.new("name", "", "query"),
    Param.new("header", "", "header"),
  ]),
  Endpoint.new("/greet2", "GET", [
    Param.new("myname", "", "query"),
    Param.new("b", "", "query"),
    Param.new("name", "", "query"),
  ]),
  # ItemController2.java
  Endpoint.new("/items2/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/items2/create", "POST", [Param.new("id", "", "form"), Param.new("name", "", "form")]),
  Endpoint.new("/items2/edit/", "PUT", [Param.new("id", "", "json"), Param.new("name", "", "json")]),
  Endpoint.new("/items2/{id}/thePath", "GET", [Param.new("id", "", "path")]),
  # EmptyController.java
  Endpoint.new("/empty/", "GET"),
  # MyController.java
  Endpoint.new("/api/v1/test/", "GET", [Param.new("name", "", "query"), Param.new("header", "", "header")]),
  # TApiResponses.java
  Endpoint.new("/multi/annotation/", "GET", [Param.new("name", "", "query"), Param.new("header", "", "header")]),
  # TRequestHeader.java
  Endpoint.new("/request/header/", "GET", [Param.new("name", "", "query"), Param.new("header", "", "header"), Param.new("AUTHORIZATION", "", "header")]),
  # DuplicateParameter.java
  Endpoint.new("/duplicate/parameter/{token}/test", "DELETE", [Param.new("token", "", "path")]),
  # ThrowsMultiException.java
  Endpoint.new("/throws/multi/exception/", "GET", [Param.new("name", "", "query"), Param.new("header", "", "header")]),
]

FunctionalTester.new("fixtures/java/spring/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
