require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/articles/", "GET", [
    Param.new("status", "", "query"),
  ]),
  Endpoint.new("/api/articles/{article_id}/", "GET", [
    Param.new("preview", "", "query"),
    Param.new("article_id", "", "path"),
  ]),
  Endpoint.new("/api/articles/{article_id}/publish/", "POST", [
    Param.new("reason", "", "form"),
    Param.new("article_id", "", "path"),
  ]),
  Endpoint.new("/api/articles/stats/", "GET", [
    Param.new("period", "", "query"),
  ]),
  Endpoint.new("/api/articles/bulk-status/", "GET", [
    Param.new("scope", "", "query"),
  ]),
  Endpoint.new("/api/articles/bulk-status/", "POST", [
    Param.new("scope", "", "query"),
  ]),
  Endpoint.new("/api/media/", "GET"),
  Endpoint.new("/api/media/{media_id}/", "GET", [
    Param.new("media_id", "", "path"),
  ]),
  Endpoint.new("/api/media/{media_id}/moderate/", "PATCH", [
    Param.new("state", "", "form"),
    Param.new("media_id", "", "path"),
  ]),
  Endpoint.new("/api/keyword-media/", "GET"),
  Endpoint.new("/api/keyword-media/{media_id}/", "GET", [
    Param.new("media_id", "", "path"),
  ]),
  Endpoint.new("/api/keyword-media/{media_id}/moderate/", "PATCH", [
    Param.new("state", "", "form"),
    Param.new("media_id", "", "path"),
  ]),
  Endpoint.new("/imported-api/library-media/", "GET"),
  Endpoint.new("/imported-api/library-media/{media_id}/", "GET", [
    Param.new("media_id", "", "path"),
  ]),
  Endpoint.new("/imported-api/library-media/{media_id}/moderate/", "PATCH", [
    Param.new("state", "", "form"),
    Param.new("media_id", "", "path"),
  ]),
  Endpoint.new("/module-include/keyword-route/", "GET", [
    Param.new("value", "", "query"),
  ]),
  Endpoint.new("/module-include/inline/nested/", "GET", [
    Param.new("nested", "", "query"),
  ]),
  Endpoint.new("/direct-articles/", "GET", [
    Param.new("status", "", "query"),
  ]),
  Endpoint.new("/direct-articles/{article_id}/", "GET", [
    Param.new("preview", "", "query"),
    Param.new("article_id", "", "path"),
  ]),
  Endpoint.new("/direct-articles/{article_id}/publish/", "POST", [
    Param.new("reason", "", "form"),
    Param.new("article_id", "", "path"),
  ]),
  Endpoint.new("/direct-articles/stats/", "GET", [
    Param.new("period", "", "query"),
  ]),
  Endpoint.new("/direct-articles/bulk-status/", "GET", [
    Param.new("scope", "", "query"),
  ]),
  Endpoint.new("/direct-articles/bulk-status/", "POST", [
    Param.new("scope", "", "query"),
  ]),
  Endpoint.new("/direct-media/", "GET"),
  Endpoint.new("/direct-media/{media_id}/", "GET", [
    Param.new("media_id", "", "path"),
  ]),
  Endpoint.new("/direct-media/{media_id}/moderate/", "PATCH", [
    Param.new("state", "", "form"),
    Param.new("media_id", "", "path"),
  ]),
  Endpoint.new("/local/reports/", "GET", [
    Param.new("owner", "", "query"),
  ]),
  Endpoint.new("/local/reports/<slug:report_slug>/", "GET", [
    Param.new("preview", "", "query"),
    Param.new("report_slug", "", "path"),
  ]),
  Endpoint.new("/namespaced/exports/", "GET", [
    Param.new("since", "", "query"),
  ]),
  Endpoint.new("/combined/", "GET", [
    Param.new("owner", "", "query"),
  ]),
  Endpoint.new("/extended/", "GET"),
  Endpoint.new("/extended/", "POST", [Param.new("token", "", "form")]),
  Endpoint.new("/", "GET"),
  Endpoint.new("/page/<int:page>/", "GET", [
    Param.new("page", "", "path"),
  ]),
  Endpoint.new("/article/<int:year>/<int:month>/<int:day>/<int:article_id>.html", "GET", [
    Param.new("year", "", "path"),
    Param.new("month", "", "path"),
    Param.new("day", "", "path"),
    Param.new("article_id", "", "path"),
    Param.new("comment_page", "", "query"),
  ]),
  Endpoint.new("/category/<slug:category_name>.html", "GET", [
    Param.new("category_name", "", "path"),
  ]),
  Endpoint.new("/category/<slug:category_name>/<int:page>.html", "GET", [
    Param.new("category_name", "", "path"),
    Param.new("page", "", "path"),
  ]),
  Endpoint.new("/author/<author_name>.html", "GET", [
    Param.new("author_name", "", "path"),
  ]),
  Endpoint.new("/author/<author_name>/<int:page>.html", "GET", [
    Param.new("author_name", "", "path"),
    Param.new("page", "", "path"),
  ]),
  Endpoint.new("/tag/<slug:tag_name>.html", "GET", [
    Param.new("tag_name", "", "path"),
  ]),
  Endpoint.new("/tag/<slug:tag_name>/<int:page>.html", "GET", [
    Param.new("tag_name", "", "path"),
    Param.new("page", "", "path"),
  ]),
  Endpoint.new("/archives.html", "GET", [Param.new("year", "", "query")]),
  Endpoint.new("/links.html", "GET"),
  Endpoint.new("/feedback/", "GET", [Param.new("topic", "", "query")]),
  Endpoint.new("/feedback/", "POST", [Param.new("message", "", "form")]),
  Endpoint.new("/upload", "GET", [Param.new("sign", "", "query"), Param.new("sign", "", "query"), Param.new("X_FORWARDED_FOR", "", "header"), Param.new("X_REAL_IP", "", "header")]),
  Endpoint.new("/upload", "POST", [Param.new("sign", "", "query"), Param.new("X_FORWARDED_FOR", "", "header"), Param.new("X_REAL_IP", "", "header")]),
  Endpoint.new("/not_found", "GET", [Param.new("app_type", "", "cookie")]),
  Endpoint.new("/test", "GET"),
  Endpoint.new("/test", "POST", [Param.new("test_param", "", "form")]),
  Endpoint.new("/test", "PUT", [Param.new("test_param", "", "form")]),
  Endpoint.new("/test", "PATCH", [Param.new("test_param", "", "form")]),
  Endpoint.new("/delete_test", "GET"),
  Endpoint.new("/delete_test", "DELETE"),
  # @require_POST → POST only (no implicit GET).
  Endpoint.new("/require_post", "POST"),
  # @require_http_methods(["GET", "POST"]) under a non-route decorator.
  Endpoint.new("/require_methods", "GET"),
  Endpoint.new("/require_methods", "POST"),
  # DeleteView → GET (confirm) + POST (delete), never HTTP DELETE.
  Endpoint.new("/widget/delete", "GET"),
  Endpoint.new("/widget/delete", "POST"),
  # DRF APIView honors explicitly defined HTTP methods only.
  Endpoint.new("/api/token/", "POST", [Param.new("token", "", "form")]),
  # DRF RetrieveUpdateAPIView maps retrieve/update to GET/PUT/PATCH,
  # and request.data inside update must not create a stray POST.
  Endpoint.new("/api/account/", "GET"),
  Endpoint.new("/api/account/", "PUT", [Param.new("display_name", "", "form")]),
  Endpoint.new("/api/account/", "PATCH", [Param.new("display_name", "", "form")]),
  Endpoint.new("/legacy/{legacy_id}/", "GET", [
    Param.new("preview", "", "query"),
    Param.new("legacy_id", "", "path"),
  ]),
  Endpoint.new("/nested/{nested_slug}_{pk}/", "GET", [
    Param.new("preview", "", "query"),
    Param.new("nested_slug", "", "path"),
    Param.new("pk", "", "path"),
  ]),
  Endpoint.new("/shop/orders/", "POST", [Param.new("token", "", "form")]),
  Endpoint.new("/shop/reports/daily/", "GET", [Param.new("period", "", "query")]),
]

FunctionalTester.new("fixtures/python/django/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
