require "../../func_spec.cr"

# #3271 (Kotlin Spring):
# - naming: class-level `@JsonNaming(SnakeCaseStrategy::class)`; an explicit
#   `@JsonProperty("NOTE")` still wins.
# - naming_global: `spring.jackson.property-naming-strategy: SNAKE_CASE` in
#   that module's application.yml; a class `@JsonNaming(LowerCamelCase)`
#   opts out of it.
# - resolver: `@CurrentAccount` is bound by a custom
#   `HandlerMethodArgumentResolver`, so it is not request input.
# - scalar: an un-annotated scalar next to a JSON `@RequestBody` is a query param.
# - header: `@RequestHeader headers: HttpHeaders` / `Map` names no header.
# - dotted_folder: a DTO under `src/main/kotlin/com.example/model` resolves.
# - root_name: `unwrap-root-value: true` nests the body under the class's
#   `@JsonRootName`, else its simple name.
tester = FunctionalTester.new("fixtures/kotlin/spring_request_params/", {
  :techs     => 1,
  :endpoints => 11,
}, [] of Endpoint)
tester.perform_tests

it "reports the wire names and locations Spring binds", tags: "functional" do
  summary = tester.endpoints.map do |endpoint|
    {"#{endpoint.method} #{endpoint.url}", endpoint.params.map { |param| "#{param.name}:#{param.param_type}" }.sort!}
  end
  summary.sort!.should eq([
    {"GET /logs", [] of String},
    {"GET /posts/{postId}", ["postId:path"]},
    {"POST /articles", ["NewArticleParam.title:json"]},
    {"POST /events/{id}", ["id:path", "type:query", "userId:json"]},
    {"POST /logs", ["message:json"]},
    {"POST /messages", ["NOTE:json", "first_name:json", "order_id:json"]},
    {"POST /messages/camel", ["firstName:json"]},
    {"POST /messages/global", ["first_name:json", "order_id:json"]},
    {"POST /posts", ["title:json"]},
    {"POST /users/login", ["user.email:json", "user.password:json"]},
    {"PUT /items", ["count:json", "title:json"]},
  ])
end
