require "../../func_spec.cr"

# Jupyter Server builds its routes as `r"/api/kernels/%s" % _kernel_id_regex`
# and `rf"/api/kernels/{_kernel_id_regex}"`; both read the module constant.
# A pattern that is still a regex after that (`/(robots\.txt|favicon\.ico)`)
# is marked `kind = "regex"`.
kid = [Param.new("kernel_id", "", "path")]
tester = FunctionalTester.new("fixtures/python/tornado_regex_const/", {
  :techs     => 1,
  :endpoints => 6,
}, [
  Endpoint.new("/api/inline/{kernel_id}", "GET", kid),
  Endpoint.new("/api/pct/{kernel_id}", "GET", kid),
  Endpoint.new("/api/pct/{kernel_id}", "DELETE", kid),
  Endpoint.new("/api/fstr/{kernel_id}", "GET", kid),
  Endpoint.new("/api/fstr/{kernel_id}", "DELETE", kid),
  Endpoint.new("/(robots.txt|favicon.ico)", "GET"),
])
tester.perform_tests

it "marks only the alternation route as a regex", tags: "functional" do
  tester.endpoints.select { |ep| ep.kind == "regex" }.map(&.url).should eq(["/(robots.txt|favicon.ico)"])
end
