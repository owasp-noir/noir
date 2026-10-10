require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/", "ANY"),
  Endpoint.new("/static/", "ANY"),
  Endpoint.new("/assets/", "ANY"),
  Endpoint.new("/healthz", "ANY"),
  # `path_reg` anchors are stripped; `path_end .php` is not a path.
  Endpoint.new("/v2/[a-z]+", "ANY"),
  # The older `url*` fetches match the path too; `url_param` does not.
  Endpoint.new("/legacy/", "ANY"),
  # Anonymous ACLs in rules; a regex quantifier's `}` does not close one.
  Endpoint.new("/v[0-9]{1,2}/admin", "ANY"),
  Endpoint.new("/internal", "ANY"),
  Endpoint.new("/public", "ANY"),
  Endpoint.new("/api/admin", "ANY"),
]

tester = FunctionalTester.new("fixtures/specification/haproxy/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "HAProxy rule tags", tags: "functional" do
  it "marks paths matched by deny rules and names the backend" do
    tags = ->(url : String) { tester.endpoints.find!(&.url.==(url)).tags.map { |tag| {tag.name, tag.description} } }
    tags.call("/internal").should contain({"haproxy-action", "deny"})
    tags.call("/api/admin").should contain({"haproxy-action", "deny"})
    # `deny unless` denies everything *but* /public.
    tags.call("/public").should_not contain({"haproxy-action", "deny"})
    tags.call("/api/").should contain({"haproxy-backend", "static_servers, api_servers"})
    tags.call("/api/").should contain({"haproxy-path-type", "prefix"})
    tags.call("/healthz").should contain({"haproxy-path-type", "exact"})
  end
end
