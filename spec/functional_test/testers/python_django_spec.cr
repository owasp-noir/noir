require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/page/<int:page>/", "GET", [
    Param.new("page", "", "path")
  ]),
  Endpoint.new("/article/<int:year>/<int:month>/<int:day>/<int:article_id>.html", "GET", [
    Param.new("year", "", "path"),
    Param.new("month", "", "path"),
    Param.new("day", "", "path"),
    Param.new("article_id", "", "path"),
    Param.new("comment_page", "", "query")
  ]),
  Endpoint.new("/category/<slug:category_name>.html", "GET", [
    Param.new("category_name", "", "path")
  ]),
  Endpoint.new("/category/<slug:category_name>/<int:page>.html", "GET", [
    Param.new("category_name", "", "path"),
    Param.new("page", "", "path")
  ]),
  Endpoint.new("/author/<author_name>.html", "GET", [
    Param.new("author_name", "", "path")
  ]),
  Endpoint.new("/author/<author_name>/<int:page>.html", "GET", [
    Param.new("author_name", "", "path"),
    Param.new("page", "", "path")
  ]),
  Endpoint.new("/tag/<slug:tag_name>.html", "GET", [
    Param.new("tag_name", "", "path")
  ]),
  Endpoint.new("/tag/<slug:tag_name>/<int:page>.html", "GET", [
    Param.new("tag_name", "", "path"),
    Param.new("page", "", "path")
  ]),
  Endpoint.new("/archives.html", "GET"),
  Endpoint.new("/links.html", "GET"),
  Endpoint.new("/upload", "GET", [Param.new("sign", "", "query"), Param.new("sign", "", "query"), Param.new("X_FORWARDED_FOR", "", "header"), Param.new("X_REAL_IP", "", "header")]),
  Endpoint.new("/upload", "POST", [Param.new("sign", "", "query"), Param.new("X_FORWARDED_FOR", "", "header"), Param.new("X_REAL_IP", "", "header")]),
  Endpoint.new("/not_found", "GET", [Param.new("app_type", "", "cookie")]),
  Endpoint.new("/test", "GET", [Param.new("test_param", "", "form")]),
  Endpoint.new("/test", "POST", [Param.new("test_param", "", "form")]),
  Endpoint.new("/test", "PUT", [Param.new("test_param", "", "form")]),
  Endpoint.new("/test", "PATCH", [Param.new("test_param", "", "form")]),
  Endpoint.new("/delete_test", "GET"),
  Endpoint.new("/delete_test", "DELETE"),
]

FunctionalTester.new("fixtures/python_django/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).test_all
