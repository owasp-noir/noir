require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/get_user", "POST", [
    Param.new("id", "", "form"),
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/api/v2/get_post", "GET", [
    Param.new("slug", "", "query"),
  ]),
  Endpoint.new("/custom/add_todo", "POST", [
    Param.new("title", "", "form"),
  ]),
  Endpoint.new("/api/list_todos", "GET", [
    Param.new("query", "", "query"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/api/save_settings", "POST", [
    Param.new("theme", "", "json"),
  ]),
  Endpoint.new("/api/todo/update", "PATCH", [
    Param.new("id", "", "json"),
    Param.new("done", "", "json"),
  ]),
  Endpoint.new("/api/counter_stream", "GET"),
  Endpoint.new("/api/commented", "GET", [
    Param.new("term", "", "query"),
  ]),
  Endpoint.new("/api/lower", "GET", [
    Param.new("type", "", "query"),
  ]),
  Endpoint.new("/api/empty_ep", "POST"),
]

# `leptos_axum` in the manifest is also axum evidence; axum finds no routes.
FunctionalTester.new("fixtures/rust/leptos/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
