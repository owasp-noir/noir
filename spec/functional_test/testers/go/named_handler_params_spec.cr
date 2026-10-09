require "../../func_spec.cr"

# Named handlers (`r.GET("/a", listA)` + `func listA`) own the accessors in
# their body. They used to land on the LAST route of the file (and be dropped
# entirely in chi). `listC` is declared above the routes, `listA`/`listB`
# below, so both declaration orders are covered.
%w[gin echo fiber chi iris hertz mux gf httprouter http fasthttp beego gozero].each do |fw|
  param_type = fw == "gozero" ? "form" : "query"
  expected_endpoints = %w[a b c].map do |id|
    Endpoint.new("/#{id}", "GET", [Param.new("q#{id}", "", param_type)])
  end

  tester = FunctionalTester.new("fixtures/go/named_handler_#{fw}/", {
    :techs     => 1,
    :endpoints => expected_endpoints.size,
  }, expected_endpoints)
  tester.perform_tests

  it "keeps #{fw} named-handler params off the last route", tags: "functional" do
    last = tester.endpoints.find! { |endpoint| endpoint.url == "/c" }
    last.params.map(&.name).should eq(["qc"])
  end
end

# Selector handlers resolve by the qualifier's declared type: `u` and `p` are
# receivers of `Users` and `Posts` (the `u, p := &Users{}, &Posts{}`
# multi-assign must not type `p` as `Users`), so neither `List` body may land
# on the other route. `handlers.Show` is a package-qualified handler next to
# an unrelated local `Show`.
ambiguous = FunctionalTester.new("fixtures/go/named_handler_ambiguous/", {
  :techs     => 1,
  :endpoints => 4,
}, nil)
ambiguous.perform_tests

private def param_names(tester : FunctionalTester, url : String) : Array(String)
  tester.endpoints.find! { |endpoint| endpoint.url == url }.params.map(&.name)
end

it "never credits a same-named method of another receiver type", tags: "functional" do
  param_names(ambiguous, "/users").should eq(["user_q"])
  param_names(ambiguous, "/posts").should eq(["post_q"])
  param_names(ambiguous, "/show").should be_empty
end

# `r.GET("/x", RateLimit(), listX)`: the handler comes after the middleware,
# and its accessors belong to `/x`, not to the inline closure registered last.
middleware = FunctionalTester.new("fixtures/go/named_handler_middleware/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/x", "GET", [Param.new("qx", "", "query")]),
  Endpoint.new("/y", "POST", [Param.new("qy", "", "query")]),
])
middleware.perform_tests

it "keeps a middleware-chained handler's params off the last route", tags: "functional" do
  param_names(middleware, "/z").should be_empty
end

# `users.List` names `*UserCtl.List` from users.go; the local
# `func (s *server) List` is another receiver type and must not be credited.
crossfile = FunctionalTester.new("fixtures/go/named_handler_crossfile_receiver/", {
  :techs     => 1,
  :endpoints => 2,
}, nil)
crossfile.perform_tests

it "does not credit a local method of another receiver type", tags: "functional" do
  param_names(crossfile, "/users").should_not contain("server_only")
end
