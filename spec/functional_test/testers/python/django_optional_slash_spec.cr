require "../../func_spec.cr"

# `re_path(r'^tags/?$')` is how a Django URLconf spells "the trailing slash
# is optional". The `?` there is a regex quantifier on the preceding `/`,
# not a character of the path, and the normalizer that already strips the
# anchors and rewrites `(?P<name>…)` used to carry it into the URL. In a
# URL a `?` is the query delimiter, so `/search/?` rendered with its query
# params came out as `/search/??q=` — the first parameter reaching the
# server named `?q` instead of `q`. Of the two paths `/?$` matches the
# shorter is reported, so it merges with a spec's `/tags`.
extracted_endpoints = [
  Endpoint.new("/tags", "GET"),
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/articles/{slug}/comments", "GET", [
    Param.new("slug", "", "path"),
  ]),
  # An optional *group* keeps the parameter — noir's URL shape has no way
  # to spell an optional segment — and drops only the quantifier.
  Endpoint.new("/feed/{page}", "GET", [
    Param.new("page", "", "path"),
  ]),
  # Implicit string concatenation, bare and parenthesised (Saleor).
  Endpoint.new("/plugins/channel/{channel_slug}/{plugin_id}/", "GET", [
    Param.new("channel_slug", "", "path"),
    Param.new("plugin_id", "", "path"),
  ]),
  Endpoint.new("/thumbnail/{instance_id}/{size}/{format}/", "GET", [
    Param.new("instance_id", "", "path"),
    Param.new("size", "", "path"),
    Param.new("format", "", "path"),
  ]),
  Endpoint.new("/image/{instance_id}/", "GET", [
    Param.new("instance_id", "", "path"),
  ]),
]

tester = FunctionalTester.new("fixtures/python/django_optional_slash/", {
  :techs     => 1,
  :endpoints => extracted_endpoints.size,
}, extracted_endpoints)
tester.perform_tests

it "leaves no regex quantifier in the emitted paths", tags: "functional" do
  tester.app.endpoints.map(&.url).select(&.includes?('?')).should be_empty
end
