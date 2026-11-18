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
#   `@JsonRootName` (also after `namespace =`), else its simple name; an
#   `@JsonUnwrapped` field inlines under the outer class's root;
#   root_name_off has no setting.
# - transient_body: Jackson skips a `transient` field unless a setter,
#   Lombok `@Setter` or `@JsonProperty` names the property; form binding
#   (`@ModelAttribute`) is unchanged.
# - type_resolver: `ShopSession` is supplied by a resolver that tests the
#   parameter type, so it is not request input; `@ModelAttribute` still binds
#   it, and a resolver that also needs an annotation (`@Tenant`) leaves the
#   bare type to Spring.
# - paging_field: a `Pageable` / `PageRequest` / `Sort` field of a command
#   object takes no single request value.
# - bean_property: a Lombok `boolean isActive` binds as `active`; a `Boolean`
#   wrapper keeps `isShared`.
# - gson_mapper: `preferred-json-mapper=gson` reads JSON by field name, so the
#   JSON key stays `isPinned` while the query name is `pinned`.
tester = FunctionalTester.new("fixtures/java/spring_request_params/", {
  :techs     => 1,
  :endpoints => 20,
}, [] of Endpoint)
tester.perform_tests

it "reports the wire names and locations Spring binds", tags: "functional" do
  summary = tester.endpoints.map do |endpoint|
    {"#{endpoint.method} #{endpoint.url}", endpoint.params.map { |param| "#{param.name}:#{param.param_type}" }.sort!}
  end
  summary.sort!.should eq([
    {"GET /flags", ["label:query", "pinned:query"]},
    {"GET /gadgets", ["computedLabel:query", "label:query", "nickname:query", "pinned:query"]},
    {"GET /gizmos/search", ["keyword:query", "page:query", "range.min:query", "size:query", "sort:query"]},
    {"GET /posts/{postId}", ["postId:path"]},
    {"GET /stores/bound", ["shopId:query", "shopName:query"]},
    {"GET /stores/{storeId}/widgets", ["limit:query", "storeId:path"]},
    {"GET /tenants/current", [] of String},
    {"GET /tenants/lookup", ["tenantCode:query"]},
    {"POST /articles", ["NewArticleParam.title:json"]},
    {"POST /badges", ["active:json", "isShared:json"]},
    {"POST /events/{id}", ["id:path", "type:query", "userId:json"]},
    {"POST /flags", ["isPinned:json", "label:json"]},
    {"POST /gadgets", ["label:json", "nickname:json", "pinned:json", "tag:json"]},
    {"POST /items", ["name:json", "price:json"]},
    {"POST /namespaced", ["named.a:json"]},
    {"POST /orders", ["shipping_address:json", "user_id:json"]},
    {"POST /sessions", ["email:json"]},
    {"POST /users/login", ["user.email:json", "user.password:json"]},
    {"POST /wrapped", ["outer.p_innerField:json"]},
    {"PUT /items", ["count:json", "title:json"]},
  ])
end
