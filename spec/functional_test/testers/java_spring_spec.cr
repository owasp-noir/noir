require "../func_spec.cr"

extected_endpoints = [
  # MyRoutingConfiguration.java
  Endpoint.new("/{user}", "GET"),
  Endpoint.new("/{user}/customers", "GET"),
  Endpoint.new("/{user}/0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_.~", "GET"),
  Endpoint.new("/{user}", "DELETE"),
  Endpoint.new("/{user}", "POST"),
  Endpoint.new("/{user}", "PUT"),
  # QuoteRouter.java
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/echo", "POST"),
  Endpoint.new("/quotes", "GET"),
  Endpoint.new("/quotes/0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_.~", "GET"),
  # ItemController.java
  Endpoint.new("/items/{id}", "GET"),
  Endpoint.new("/items/json/{id}", "GET"),
  Endpoint.new("/items", "POST"),
  Endpoint.new("/items/update/{id}", "PUT"),
  Endpoint.new("/items/delete/{id}", "DELETE"),
  Endpoint.new("/greet", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/greet2", "GET", [
    Param.new("myname", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/java_spring/", {
  :techs     => 1,
  :endpoints => 17,
}, extected_endpoints).test_all
