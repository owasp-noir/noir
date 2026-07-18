require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/add", "GET", [Param.new("a", "", "query"), Param.new("b", "", "query")]),
  Endpoint.new("/api/items", "POST", [
    Param.new("name", "", "json"),
    Param.new("price", "", "json"),
    Param.new("quantity", "1", "json"),
  ]),
  Endpoint.new("/api/items/{item_id}", "GET", [
    Param.new("item_id", "", "path"),
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/api/items/{item_id}", "PUT", [
    Param.new("item_id", "", "path"),
    Param.new("name", "", "json"),
    Param.new("price", "", "json"),
    Param.new("quantity", "1", "json"),
  ]),
  Endpoint.new("/api/search", "GET", [Param.new("q", "", "query"), Param.new("limit", "10", "query")]),
  Endpoint.new("/api/upload", "POST", [Param.new("note", "", "form"), Param.new("attachment", "", "form")]),
  Endpoint.new("/api/whoami", "GET", [Param.new("x_api_key", "", "header"), Param.new("session", "", "cookie")]),
  # Body schema imported from another module (`from myproject.schemas import BlogIn`),
  # declared on a multi-line decorator.
  Endpoint.new("/api/blogs", "POST", [
    Param.new("title", "", "json"),
    Param.new("body", "", "json"),
    Param.new("published", "False", "json"),
  ]),
  # @api.api_operation(["POST", "PATCH"], "/mixed") emits one endpoint per verb.
  Endpoint.new("/api/mixed", "POST"),
  Endpoint.new("/api/mixed", "PATCH"),
  # Router mounted with `api.add_router("/events/", events_router)`.
  Endpoint.new("/api/events/", "GET"),
  Endpoint.new("/api/events/{event_id}", "GET", [Param.new("event_id", "", "path")]),
  # Router mounted with the dotted-string form `api.add_router("/news/", "news.api.router")`.
  Endpoint.new("/api/news/latest", "GET", [Param.new("page", "1", "query")]),
  # Router mounted via a module-attribute reference: `from blog import api as
  # blog_api` + `api.add_router("/blog/", blog_api.router)`.
  Endpoint.new("/api/blog/recent", "GET", [Param.new("tag", "", "query")]),
  # Emitted by the Django analyzer: `path("api/", api.urls)` in urls.py
  # can't resolve `api.urls` to a view, so it falls back to one GET. Both
  # `python_django` and `python_django_ninja` fire on this project.
  Endpoint.new("/api/", "GET"),
]

tester = FunctionalTester.new("fixtures/python/django_ninja/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests
