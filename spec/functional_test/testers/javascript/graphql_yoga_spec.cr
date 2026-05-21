require "../../func_spec.cr"

# Default standalone Yoga: `createYoga({ schema: createSchema({ typeDefs: \`...\` }) })`.
# 2 Query + 1 Mutation + 1 Subscription = 4 endpoints on the default /graphql mount.
FunctionalTester.new("fixtures/javascript/graphql_yoga/common/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  Endpoint.new("/graphql#Query.hello", "POST", [
    Param.new("graphql_query_hello", "", "json"),
  ]),
  Endpoint.new("/graphql#Query.user", "POST", [
    Param.new("id", "", "json"),
    Param.new("graphql_query_user", "", "json"),
  ]),
  Endpoint.new("/graphql#Mutation.signin", "POST", [
    Param.new("email", "", "json"),
    Param.new("password", "", "json"),
    Param.new("graphql_mutation_signin", "", "json"),
  ]),
  Endpoint.new("/graphql#Subscription.clock", "POST", [
    Param.new("graphql_subscription_clock", "", "json"),
  ]),
]).perform_tests

# `graphqlEndpoint: '/api/graphql'` — host-framework-mounted Yoga.
FunctionalTester.new("fixtures/javascript/graphql_yoga/custom_endpoint/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/api/graphql#Query.products", "POST", [
    Param.new("category", "", "json"),
    Param.new("graphql_query_products", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Mutation.addToCart", "POST", [
    Param.new("productId", "", "json"),
    Param.new("quantity", "", "json"),
    Param.new("graphql_mutation_addToCart", "", "json"),
  ]),
]).perform_tests

# `const typeDefs = \`...\`; createSchema({ typeDefs })` — the const
# declaration itself carries the SDL, so the shorthand reference at the
# call site needs no special handling.
FunctionalTester.new("fixtures/javascript/graphql_yoga/const_ref/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/graphql#Query.ping", "POST", [
    Param.new("graphql_query_ping", "", "json"),
  ]),
  Endpoint.new("/graphql#Mutation.publish", "POST", [
    Param.new("channel", "", "json"),
    Param.new("body", "", "json"),
    Param.new("graphql_mutation_publish", "", "json"),
  ]),
]).perform_tests
