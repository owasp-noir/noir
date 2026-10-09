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

# Ambiguous references keep the legacy attribution instead of crediting a
# body to every route that names it: two receivers with a `List` method, and
# a package-qualified `handlers.Show` next to an unrelated local `Show`.
ambiguous = FunctionalTester.new("fixtures/go/named_handler_ambiguous/", {
  :techs     => 1,
  :endpoints => 4,
}, nil)
ambiguous.perform_tests

it "does not credit an ambiguous same-named method to every route", tags: "functional" do
  %w[/users /posts /show].each do |url|
    ambiguous.endpoints.find! { |endpoint| endpoint.url == url }.params.should be_empty
  end
end
