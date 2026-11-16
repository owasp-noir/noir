require "../../func_spec.cr"

# A sub-router built by a method on a variable bound just above the Mount
# (`h := tags.NewHandler()` then `r.Mount("/tags", h.Routes())`, or
# `comments := &commentsResource{}`) keeps its mount prefix, as the chained
# `tags.NewHandler().Routes()` does. Without it the sub-router's `/` merged
# into the root router's own `/`, which the endpoint count catches.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/tags/", "GET"),
  Endpoint.new("/tags/{slug}", "GET", [Param.new("slug", "", "path")]),
  Endpoint.new("/tags/{slug}", "DELETE", [Param.new("slug", "", "path")]),
  Endpoint.new("/comments/", "GET"),
]

tester = FunctionalTester.new("fixtures/go/chi_mount_receiver_var/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "keeps the root route's own handler", tags: "functional" do
  tester.endpoints.find! { |ep| ep.url == "/" }.handler.try(&.name).should eq("index")
end
