require "../../func_spec.cr"

# JDK built-in HTTP server (com.sun.net.httpserver.HttpServer). Paths
# come from createContext("/x", handler); verbs/params come from the
# resolved handler body (lambda, named/anonymous HttpHandler, or method
# reference). A handler with no getRequestMethod() branch defaults to GET.
expected_endpoints = [
  # Lambda, no method guard.
  Endpoint.new("/", "GET"),
  # Lambda branching on getRequestMethod() -> two verbs, body only on POST.
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  # Lambda reading a request header.
  Endpoint.new("/profile", "GET", [
    Param.new("X-Trace-Id", "", "header"),
  ]),
  # Named HttpHandler class resolved in the same file.
  Endpoint.new("/upload", "POST", [
    Param.new("body", "", "json"),
  ]),
  # Anonymous HttpHandler with "VERB".equals(getRequestMethod()) form.
  Endpoint.new("/settings", "PUT", [
    Param.new("X-Mode", "", "header"),
    Param.new("body", "", "json"),
  ]),
  # Method reference handler.
  Endpoint.new("/health", "GET"),
  # Path from a String constant + switch on the method variable.
  Endpoint.new("/api", "GET"),
  Endpoint.new("/api", "DELETE"),
  # Single-argument createContext.
  Endpoint.new("/status", "GET"),
]

tester = FunctionalTester.new("fixtures/java/httpserver/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "does not surface a body param on the GET branch of a method-dispatching handler" do
  users_get = tester.app.endpoints.find { |e| e.url == "/users" && e.method == "GET" }
  users_get.should_not be_nil
  users_get.try do |endpoint|
    endpoint.params.any? { |param| param.name == "body" }.should be_false
  end
end

it "excludes createContext routes declared under src/test/" do
  tester.app.endpoints.any? { |e| e.url == "/should-not-appear" }.should be_false
end
