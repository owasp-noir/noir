require "../../func_spec.cr"

# #3271 (Java Spring):
# - naming: a class-level `@JsonNaming(SnakeCaseStrategy.class)` renames the
#   JSON keys.
# - resolver: `@CurrentAccount` is bound by a custom
#   `HandlerMethodArgumentResolver` (`hasParameterAnnotation(CurrentAccount.class)`),
#   so it is not request input.
# - scalar: an un-annotated scalar next to a JSON `@RequestBody` is a query
#   param; a request cannot carry a JSON body and a form body at once.
# - dotted_folder: DTOs under package folders spelled with dots
#   (`src/main/java/com.example/model`, `com.example.dto`) resolve.
# - root_name: `UNWRAP_ROOT_VALUE=true` nests the body under the class's
#   `@JsonRootName`, else its simple name; root_name_off has no setting.
tester = FunctionalTester.new("fixtures/java/spring_request_params/", {
  :techs     => 1,
  :endpoints => 8,
}, [] of Endpoint)
tester.perform_tests

it "reports the wire names and locations Spring binds", tags: "functional" do
  summary = tester.endpoints.map do |endpoint|
    {"#{endpoint.method} #{endpoint.url}", endpoint.params.map { |param| "#{param.name}:#{param.param_type}" }.sort!}
  end
  summary.sort!.should eq([
    {"GET /posts/{postId}", ["postId:path"]},
    {"POST /articles", ["NewArticleParam.title:json"]},
    {"POST /events/{id}", ["id:path", "type:query", "userId:json"]},
    {"POST /items", ["name:json", "price:json"]},
    {"POST /orders", ["shipping_address:json", "user_id:json"]},
    {"POST /sessions", ["email:json"]},
    {"POST /users/login", ["user.email:json", "user.password:json"]},
    {"PUT /items", ["count:json", "title:json"]},
  ])
end
