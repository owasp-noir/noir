require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/page/<int:page>/", "GET"),
  Endpoint.new("/article/<int:year>/<int:month>/<int:day>/<int:article_id>.html", "GET", [Param.new("comment_page", "", "query")]),
  Endpoint.new("/category/<slug:category_name>.html", "GET"),
  Endpoint.new("/category/<slug:category_name>/<int:page>.html", "GET"),
  Endpoint.new("/author/<author_name>.html", "GET"),
  Endpoint.new("/author/<author_name>/<int:page>.html", "GET"),
  Endpoint.new("/tag/<slug:tag_name>.html", "GET"),
  Endpoint.new("/tag/<slug:tag_name>/<int:page>.html", "GET"),
  Endpoint.new("/archives.html", "GET"),
  Endpoint.new("/links.html", "GET"),
  Endpoint.new("/upload", "GET", [Param.new("sign", "", "query"), Param.new("sign", "", "query"), Param.new("X_FORWARDED_FOR", "", "header"), Param.new("X_REAL_IP", "", "header")]),
  Endpoint.new("/upload", "POST", [Param.new("sign", "", "query"), Param.new("X_FORWARDED_FOR", "", "header"), Param.new("X_REAL_IP", "", "header")]),
  Endpoint.new("/not_found", "GET", [Param.new("Cookie['app_type']", "", "header")]),
  Endpoint.new("/test", "GET", [Param.new("test_param", "", "form")]),
  Endpoint.new("/test", "POST", [Param.new("test_param", "", "form")]),
  Endpoint.new("/test", "PUT", [Param.new("test_param", "", "form")]),
  Endpoint.new("/test", "PATCH", [Param.new("test_param", "", "form")]),
  Endpoint.new("/delete_test", "GET"),
  Endpoint.new("/delete_test", "DELETE"),
]

FunctionalTester.new("fixtures/django/", {
  :techs     => 1,
  :endpoints => 20,
}, extected_endpoints).test_all
