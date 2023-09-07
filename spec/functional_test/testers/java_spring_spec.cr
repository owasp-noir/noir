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
]

FunctionalTester.new("fixtures/java_spring/", {
  :techs     => 1,
  :endpoints => 15,
}, extected_endpoints).test_all
