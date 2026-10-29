require "../../func_spec.cr"

# #3271 (Kotlin Spring):
# - naming: class-level `@JsonNaming(SnakeCaseStrategy::class)`; an explicit
#   `@JsonProperty("NOTE")` still wins.
# - naming_global: `spring.jackson.property-naming-strategy: SNAKE_CASE` in
#   that module's application.yml.
# - resolver: `@CurrentAccount` is bound by a custom
#   `HandlerMethodArgumentResolver`, so it is not request input.
# - scalar: an un-annotated scalar next to a JSON `@RequestBody` is a query param.
# - header: `@RequestHeader headers: HttpHeaders` / `Map` names no header.
tester = FunctionalTester.new("fixtures/kotlin/spring_request_params/", {
  :techs     => 1,
  :endpoints => 7,
}, [] of Endpoint)
tester.perform_tests

it "reports the wire names and locations Spring binds", tags: "functional" do
  summary = tester.endpoints.map do |endpoint|
    {"#{endpoint.method} #{endpoint.url}", endpoint.params.map { |param| "#{param.name}:#{param.param_type}" }.sort!}
  end
  summary.sort!.should eq([
    {"GET /logs", [] of String},
    {"GET /posts/{postId}", ["postId:path"]},
    {"POST /events/{id}", ["id:path", "type:query", "userId:json"]},
    {"POST /logs", ["message:json"]},
    {"POST /messages", ["NOTE:json", "first_name:json", "order_id:json"]},
    {"POST /messages/global", ["first_name:json", "order_id:json"]},
    {"POST /posts", ["title:json"]},
  ])
end
