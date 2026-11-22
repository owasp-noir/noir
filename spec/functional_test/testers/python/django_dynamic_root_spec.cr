require "../../func_spec.cr"

# Regression: a whole-repo scan must not report fewer routes than a scan
# of one of its subdirectories.
#
# `project/urls.py` here is the shape that broke that property in the
# wild (authentik's `authentik/root/urls.py`): a root urlconf that
# `ROOT_URLCONF` points at, but which assembles most of `urlpatterns`
# in an import-time loop the analyzer cannot follow. The anchored pass
# therefore resolves, and returns a small *non-empty* set — the two
# literal `path()` entries. The orphan-urlconf pass used to be gated on
# that set being empty, so a single resolvable-but-uninformative root
# made every other `urls.py` in the tree unreachable, and the three
# `apps/account/` routes below were reported only when the scanner was
# pointed at `apps/account/` directly.
#
# The fixture is deliberately polyglot (a Go sibling under `gateway/`),
# because that is what distinguishes this from a single-framework
# fixture: widening the Django pass must not let it reach into a
# neighbouring framework's files, and the Go routes must be unchanged.
#
# Two properties the endpoint list pins down:
#
#   * `apps/account/urls.py` is mounted only through the dynamic loop,
#     so its routes are recovered app-relative — there is no prefix to
#     recover.
#   * `apps/billing/urls.py` is reached by a literal `include()`, so it
#     appears once under `billing/` and never a second time as a bare
#     `/invoices/`. That is the false positive the old gate was there to
#     prevent, and `@visited_url_paths` is what keeps preventing it.
extracted_endpoints = [
  Endpoint.new("/optional/", "GET"),
  Endpoint.new("/-/health/", "GET"),
  Endpoint.new("/billing/invoices/", "GET"),
  Endpoint.new("/profile/", "GET"),
  Endpoint.new("/tokens/", "GET"),
  Endpoint.new("/tokens/<uuid:pk>/", "GET", [Param.new("pk", "", "path")]),
  Endpoint.new("/gateway/status", "GET"),
]

tester = FunctionalTester.new("fixtures/python/django_dynamic_root/", {
  :techs     => 2,
  :endpoints => 13,
}, extracted_endpoints)
tester.perform_tests

describe "django_dynamic_root route resolution", tags: "functional" do
  it "records the evidence for each reported route" do
    tester.endpoints.find! { |ep| ep.url == "/optional/" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/profile/" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/tokens/" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/tokens/<uuid:pk>/" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/billing/invoices/" }.resolution.should be_nil
    tester.endpoints.find! { |ep| ep.url == "/-/health/" }.resolution.should be_nil
  end
end
