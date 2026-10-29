require "../../func_spec.cr"

# Zulip's root URLconf: a helper list bound with an annotation and
# `list(...)`, extended with `+=`, then added to `urlpatterns` next to
# `i18n_patterns(*i18n_urls)`; and its `rest_path(route, GET=view, ...)`
# wrapper, whose keyword names are the verbs (a `(view, flags)` tuple
# names its view first). A wrapper without verb keywords
# (`distill_path`) reads like `path`.
tester = FunctionalTester.new("fixtures/python/django_urls_augmented/", {
  :techs     => 1,
  :endpoints => 9,
}, [
  Endpoint.new("/about/", "GET"),
  Endpoint.new("/api/v1/users/me/extra", "GET"),
  Endpoint.new("/api/v1/users/me/register", "POST"),
  Endpoint.new("/login/", "GET"),
  Endpoint.new("/{lang}/login/", "GET", [Param.new("lang", "", "path")]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/v1/users/me", "GET"),
  Endpoint.new("/api/v1/users/me", "PATCH"),
  Endpoint.new("/api/v1/users/me/plain", "GET"),
])
tester.perform_tests

describe "Django augmented url lists", tags: "functional" do
  it "points each route at its view and its urls.py line" do
    lines = tester.endpoints.to_h do |ep|
      {"#{ep.method} #{ep.url}", ep.details.code_paths.find(&.path.ends_with?("urls.py")).try(&.line)}
    end
    lines["GET /login/"].should eq(16)
    lines["GET /{lang}/login/"].should eq(16)
    lines["GET /health"].should eq(23)
    lines["PATCH /api/v1/users/me"].should eq(9)
    lines["GET /api/v1/users/me/extra"].should eq(13)
    patch = tester.endpoints.find! { |ep| ep.method == "PATCH" }
    patch.details.code_paths.any? { |p| p.path.ends_with?("views.py") && p.line == 16 }.should be_true
  end
end
