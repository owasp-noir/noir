require "../../func_spec.cr"

# chi handlers are stdlib handlers, read as net/http's are: a query string
# read through `q := r.URL.Query()`, the fields of a decoded JSON body (no
# generic `body` marker), `r.PostForm.Get` / `r.Form.Get` / `r.Form[...]`,
# and two reads on one line; in an inline closure and in a mounted
# sub-router's named handler too.
expected_endpoints = [
  Endpoint.new("/orders", "GET", [Param.new("page", "", "query"), Param.new("limit", "", "query"), Param.new("tag", "", "query"), Param.new("debug", "", "query")]),
  Endpoint.new("/orders", "POST", [Param.new("sku", "", "json"), Param.new("quantity", "", "json"), Param.new("coupon", "", "json")]),
  Endpoint.new("/stream", "POST", [Param.new("sku", "", "json"), Param.new("quantity", "", "json"), Param.new("coupon", "", "json")]),
  Endpoint.new("/render", "POST", [Param.new("sku", "", "json"), Param.new("quantity", "", "json"), Param.new("coupon", "", "json")]),
  Endpoint.new("/cursor", "GET", [Param.new("cursor", "", "query")]),
  Endpoint.new("/ignored", "POST"),
  Endpoint.new("/bytes", "POST", [Param.new("X-Codec", "", "header"), Param.new("sku", "", "json"), Param.new("quantity", "", "json"), Param.new("coupon", "", "json")]),
  Endpoint.new("/orders/{id}", "PUT", [Param.new("status", "", "form"), Param.new("note", "", "form"), Param.new("labels", "", "form"), Param.new("id", "", "path")]),
  Endpoint.new("/orders/search", "GET", [Param.new("from", "", "query"), Param.new("to", "", "query")]),
  Endpoint.new("/inline", "POST", [Param.new("dry_run", "", "query"), Param.new("sku", "", "json"), Param.new("quantity", "", "json"), Param.new("coupon", "", "json")]),
  Endpoint.new("/admin/orders", "GET", [Param.new("page", "", "query"), Param.new("limit", "", "query"), Param.new("tag", "", "query"), Param.new("debug", "", "query")]),
]

tester = FunctionalTester.new("fixtures/go/chi_stdlib_params/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "chi stdlib handler params", tags: "functional" do
  it "adds no body marker beside decoded fields" do
    tester.app.endpoints.each { |ep| ep.params.map(&.name).should_not contain("body") }
  end
end
