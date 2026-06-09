require "../../func_spec.cr"

# Regression test for --include-callee on Spring (Kotlin) (#1366).
# Mirrors the Java Spring callees spec — both analyzers reuse a
# tree-sitter parse already produced for route and parameter
# extraction to walk the matching `function_declaration` body for
# 1-hop callees.
#
# Cross-file definition resolution is intentionally out of scope for
# this first cut; `Callee#path` therefore points at the call site,
# matching the honest scope on every other analyzer.
#
# Coverage:
#   - POST /api/users/        — bare-static (`AuditLog.write`),
#                               selector-on-identifier (`service.save`),
#                               injected service expansion
#                               (`auditGateway.record`), and Kotlin
#                               collection/check/Optional unwrap noise
#                               and timestamp factory filtering while
#                               preserving real collaborator
#                               `client.get` calls.
#   - GET  /api/users/profile — `this.foo` receiver shape.
#   - GET  /api/orders/legacy — chained-on-call
#                               (`getLegacy().toString()`) drops the
#                               outer `toString` and keeps only the
#                               inner `getLegacy`.
#   - GET  /api/teams/{nation} — constructor-injected service/API
#                                 handler calls are expanded far
#                                 enough to expose outbound HTTP.
#   - GET  /api/webclient/{id} — generic same-class wrapper helpers are
#                                hidden after expansion while preserving
#                                their outbound client callees.
#   - PUT  /api/cities/{id}    — constructor-injected interface
#                                 service calls are expanded into the
#                                 single visible implementation.
#   - POST /api/budget/priority — callee budget preserves higher-value
#                                 mutating calls over repeated broad
#                                 read calls when the cap is reached.
#   - POST /graphql#Query.articles — injected GraphQL service
#                                    expansion filters Flow conversion
#                                    noise (`articles.asFlow`).
#   - POST /graphql#Mutation.createArticle — injected GraphQL service
#                                             expansion preserves an
#                                             in-memory collection write
#                                             sink (`articles.add`).
#   - POST /api/scoped     — method expansion prefers the same module
#                             when duplicate package/class names exist
#                             in sibling modules.
expected_endpoints = [
  Endpoint.new("/api/users/", "POST").tap do |ep|
    ep.push_callee(Callee.new("service.save", line: 14))
    ep.push_callee(Callee.new("AuditLog.write", line: 15))
    ep.push_callee(Callee.new("auditGateway.record", line: 15))
    ep.push_callee(Callee.new("auditGateway.find", line: 16))
    ep.push_callee(Callee.new("client.get", line: 20))
  end,

  Endpoint.new("/api/users/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("this.buildProfile", line: 21))
    ep.push_callee(Callee.new("AuditLog.write", line: 22))
  end,

  Endpoint.new("/api/orders/legacy", "GET").tap do |ep|
    ep.push_callee(Callee.new("AuditLog.write", line: 13))
    ep.push_callee(Callee.new("getLegacy", line: 14))
  end,

  Endpoint.new("/api/teams/{nation}", "GET").tap do |ep|
    ep.push_callee(Callee.new("searchEngine.getFilteredNames", line: 13))
    ep.push_callee(Callee.new("getTeams", line: 5))
    ep.push_callee(Callee.new("footballTeamsApiHandler.getAllPages", line: 11))
    ep.push_callee(Callee.new("getResponse", line: 7))
    ep.push_callee(Callee.new("restTemplate.getForObject", line: 12))
  end,

  Endpoint.new("/api/webclient/{id}", "GET").tap do |ep|
    ep.push_callee(Callee.new("client.get", line: 16))
  end,

  Endpoint.new("/api/cities/{id}", "PUT").tap do |ep|
    ep.push_callee(Callee.new("cityService.updateCity", line: 13))
    ep.push_callee(Callee.new("cityRepository.findById", line: 5))
    ep.push_callee(Callee.new("cityRepository.save", line: 6))
  end,

  Endpoint.new("/api/budget/priority", "POST").tap do |ep|
    ep.push_callee(Callee.new("budgetService.priority", line: 12))
    ep.push_callee(Callee.new("budgetRepository.save", line: 27))
    ep.push_callee(Callee.new("budgetRepository.deleteById", line: 28))
  end,

  Endpoint.new("/graphql#Query.articles", "POST").tap do |ep|
    ep.push_callee(Callee.new("articleService.findAllArticles", line: 14))
  end,

  Endpoint.new("/graphql#Mutation.createArticle", "POST").tap do |ep|
    ep.push_callee(Callee.new("articleService.createArticle", line: 19))
    ep.push_callee(Callee.new("articles.add", line: 34))
  end,

  Endpoint.new("/api/scoped", "POST").tap do |ep|
    ep.push_callee(Callee.new("localRepository.save", line: 12))
    ep.push_callee(Callee.new("databaseClient.insert", line: 18))
  end,

  Endpoint.new("/api/roles/types", "GET").tap do |ep|
    ep.push_callee(Callee.new("RoleType.entries", line: 17))
  end,

  Endpoint.new("/api/env/password", "GET").tap do |ep|
    ep.push_callee(Callee.new("EnvController.password", line: 14))
  end,
]

FunctionalTester.new("fixtures/kotlin/spring_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests

describe "--ai-context on Kotlin Spring constructor-injected callee expansion" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "surfaces outbound HTTP in injected service/API handler call chains" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring_callees/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/teams/{nation}" }
    context = endpoint.ai_context.should_not be_nil
    context.callees.map(&.name).should contain("footballTeamsApiHandler.getAllPages")
    context.callees.map(&.name).should contain("restTemplate.getForObject")
    context.callees.map(&.name).should_not contain("filterByTitlesWonAndValuation")
    context.callees.map(&.name).should_not contain("sortByValueThenName")
    context.sinks.map(&.name).should contain("restTemplate.getForObject https://example.com/$nation")

    webclient = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/webclient/{id}" }
    names = webclient.callees.map(&.name)
    names.should contain("client.get")
    names.should_not contain("withDetails")

    graphql_query = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/graphql#Query.articles" }
    graphql_query.callees.map(&.name).should contain("articleService.findAllArticles")
    graphql_query.callees.map(&.name).should_not contain("articles.asFlow")

    env = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/env/password" }
    env.callees.map(&.name).should contain("EnvController.password")
    env.ai_context.not_nil!.signals.map(&.name).should contain("Spring @Value PASS -> password")
    env.ai_context.not_nil!.sources.map(&.name).should contain("Spring @Value PASS -> password")
  end

  it "filters Kotlin collection/check noise while preserving injected collaborator callees" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring_callees/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/users/" }
    names = endpoint.callees.map(&.name)

    names.should contain("service.save")
    names.should contain("AuditLog.write")
    names.should contain("auditGateway.record")
    names.should contain("auditGateway.find")
    names.should contain("client.get")
    names.should_not contain("mutableSetOf")
    names.should_not contain("roles.add")
    names.should_not contain("roles.find")
    names.should_not contain("roles.firstOrNull")
    names.should_not contain("roles.forEach")
    names.should_not contain("roles.maxByOrNull")
    names.should_not contain("roles.indexOfFirst")
    names.should_not contain("roles.removeIf")
    names.should_not contain("roles.none")
    names.should_not contain("optionalUser.map")
    names.should_not contain("name.isBlank")
    names.should_not contain("name.isNullOrBlank")
    names.should_not contain("name.lowercase")
    names.should_not contain("CityResource.fromDto")
    names.should_not contain("ProductMapper.toResponse")
    names.should_not contain("ProductMapper.toEntity")
    names.should_not contain("mapToDto")
    names.should_not contain("UserDto.toDomain")
    names.should_not contain("CityEntity.fromDto")
    names.should_not contain("User.create")
    names.should_not contain("jwtService.getRefreshTokenCookieName")
    names.should_not contain("jwtService.getRefreshTokenExpirationTime")
    names.should_not contain("name.toDto")
    names.should_not contain("mapping")
    names.should_not contain("node")
    names.should_not contain("match")
    names.should_not contain("nodeComment.property")
    names.should_not contain("literalOf")
    names.should_not contain("where")
    names.should_not contain("count")
    names.should_not contain("query")
    names.should_not contain("random.nextInt")
    names.should_not contain("verificationToken.expiryDate.isBefore")
    names.should_not contain("session.expiryDate.isAfter")
    names.should_not contain("existing.get")
    names.should_not contain("java.util.Optional.of")
    names.should_not contain("LocalDateTime.now")
    names.should_not contain("delay")
    names.should_not contain("requireNotNull")

    context = endpoint.ai_context.should_not be_nil
    context.validators.map(&.kind).should contain("expiry_validation")
    context.validators.any?(&.name.starts_with?("expiryDate.isBefore")).should be_true
  end

  it "keeps higher-value mutating callees when the Kotlin Spring callee budget is full" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring_callees/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/budget/priority" }
    names = endpoint.callees.map(&.name)

    endpoint.callees.size.should eq(Callee::MAX_PER_ENDPOINT)
    names.should contain("budgetRepository.save")
    names.should contain("budgetRepository.deleteById")
    names.count(&.starts_with?("budgetRepository.findAll")).should be < 9
  end
end
