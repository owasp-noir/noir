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
  Endpoint.new("/upload", "GET", [Param.new("sign", "", "query"), Param.new("sign", "", "query"), Param.new("x-forwarded-for", "", "header")]),
  Endpoint.new("/upload", "POST", [Param.new("sign", "", "query"), Param.new("x-forwarded-for", "", "header")]),
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
  # @api_view pins the verb set; request.data must not widen it.
  Endpoint.new("/api_view_post", "POST", [Param.new("title", "", "form")]),
  Endpoint.new("/api_view_get", "GET"),
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
  # `self.add_view = get_class("fixture_shop.views", "BasketAddView")` in
  # the AppConfig's `ready()`: the class resolves through the loader call,
  # and its `http_method_names = ["post"]` replaces the GET+POST a
  # `FormView` would otherwise imply. `VoucherRemoveView` inherits the
  # allowlist from a base in the same file.
  Endpoint.new("/shop/add/<int:pk>/", "POST", [
    Param.new("quantity", "", "form"),
    Param.new("pk", "", "path"),
  ]),
  Endpoint.new("/shop/vouchers/<int:pk>/remove/", "POST", [Param.new("pk", "", "path")]),
  # `views.CatalogueView` is only a `get_classes(...)` re-binding; the
  # class sits behind it and an `import ... as` in `search/__init__.py`.
  Endpoint.new("/shop/catalogue/", "GET", [Param.new("sort", "", "query")]),
  # Django's `PasswordResetView` is a FormView outside the scan.
  Endpoint.new("/shop/password-reset/", "GET"),
  Endpoint.new("/shop/password-reset/", "POST"),
  Endpoint.new("/shop/login/", "GET"),
  # `urlpatterns += i18n_patterns(path('intl/', ...))` serves `/en/intl/`;
  # `{lang}` stands for the language-code segment so a real request path
  # still traces to the route.
  Endpoint.new("/{lang}/intl/", "GET", [
    Param.new("period", "", "query"),
    Param.new("lang", "", "path"),
  ]),
  # `core/api/urls.py` is reached only through
  # `path(settings.BASE_PATH, include(api_patterns))` in the root urlconf, so
  # these two endpoints exercise the whole chain that used to break:
  #
  #   1. the mount prefix is a settings attribute, not a string literal — the
  #      entry used to be discarded outright, taking every route it mounts
  #      with it (NetBox hangs its entire URL tree off exactly this line);
  #   2. `include('core.api.urls')` sits inside a urlpatterns list held in a
  #      local variable, a branch that did not follow the dotted-module form
  #      and emitted a bare GET on the mount point instead;
  #   3. the app itself publishes `urlpatterns = router.urls` off a
  #      `DefaultRouter` subclass declared in another module.
  #
  # The `/api/core/` prefix is the assertion that matters: it is what
  # separates a REST route from the identically-named web UI one.
  Endpoint.new("/api/core/nodes/", "GET", [Param.new("region", "", "query")]),
  Endpoint.new("/api/core/nodes/{pk}/", "GET", [Param.new("pk", "", "path")]),
]

tester = FunctionalTester.new("fixtures/python/django/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Django route lines", tags: "functional" do
  # Each `path(...)` entry carries its own line, whether it sits in a
  # `urlpatterns` list, an AppConfig's `get_urls`, or the `path()` that
  # mounts that app config, so `noir reach apps.py:24` can order by it.
  it "points each urlconf and app-config entry at its path() line" do
    lines = tester.endpoints.to_h do |ep|
      {"#{ep.method} #{ep.url}", ep.details.code_paths.map { |cp| "#{File.basename(cp.path)}:#{cp.line}" }}
    end
    lines["POST /shop/add/<int:pk>/"].should eq(["views.py:10", "apps.py:29", "urls.py:56"])
    lines["POST /shop/vouchers/<int:pk>/remove/"].should eq(["views.py:22", "apps.py:30", "urls.py:56"])
    lines["GET /shop/reports/daily/"].should eq(["views.py:506", "apps.py:12", "apps.py:28", "urls.py:56"])
    lines["GET /{lang}/intl/"].should eq(["views.py:506", "urls.py:62"])
  end
end

describe "Django view resolution past the urlconf", tags: "functional" do
  handlers = tester.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep.handler} }

  it "follows a module-level re-export to the class that handles the route" do
    handler = handlers["GET /shop/catalogue/"].not_nil!
    handler.name.should eq("BrowseView")
    handler.path.not_nil!.should end_with("fixture_shop/search/catalogue.py")
    handler.line.should eq(6)
  end

  it "names Django's own view as the handler, without a location" do
    %w[GET POST].each do |method|
      handler = handlers["#{method} /shop/password-reset/"].not_nil!
      handler.name.should eq("auth_views.PasswordResetView")
      handler.path.should be_nil
    end
  end

  it "leaves a same-named view from another package unnamed" do
    handlers["GET /shop/login/"].should be_nil
    handlers.has_key?("POST /shop/login/").should be_false
  end
end
