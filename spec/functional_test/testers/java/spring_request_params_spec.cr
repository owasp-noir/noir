require "../../func_spec.cr"

# #3271 (Java Spring):
# - naming: a class-level `@JsonNaming(SnakeCaseStrategy.class)` renames the
#   JSON keys.
# - resolver: `@CurrentAccount` is bound by a custom
#   `HandlerMethodArgumentResolver` (`hasParameterAnnotation(CurrentAccount.class)`),
#   so it is not request input.
# - scalar: an un-annotated scalar next to a JSON `@RequestBody` is a query
#   param; a request cannot carry a JSON body and a form body at once.
tester = FunctionalTester.new("fixtures/java/spring_request_params/", {
  :techs     => 1,
  :endpoints => 3,
}, [] of Endpoint)
tester.perform_tests

it "reports the wire names and locations Spring binds", tags: "functional" do
  summary = tester.endpoints.map do |endpoint|
    {"#{endpoint.method} #{endpoint.url}", endpoint.params.map { |param| "#{param.name}:#{param.param_type}" }.sort!}
  end
  summary.sort!.should eq([
    {"GET /posts/{postId}", ["postId:path"]},
    {"POST /events/{id}", ["id:path", "type:query", "userId:json"]},
    {"POST /orders", ["shipping_address:json", "user_id:json"]},
  ])
end
