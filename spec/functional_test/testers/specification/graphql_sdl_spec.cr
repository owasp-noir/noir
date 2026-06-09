require "../../func_spec.cr"

# common: 3 Query + 2 Mutation + 1 Subscription = 6 endpoints.
# URLs use a `/graphql#<RootType>.<field>` fragment so the optimizer's
# (method, url) dedupe keeps each operation distinct.
FunctionalTester.new("fixtures/specification/graphql_sdl/common/", {
  :techs     => 1,
  :endpoints => 6,
}, [
  Endpoint.new("/graphql#Query.user", "POST", [
    Param.new("id", "", "json"),
    Param.new("graphql_query_user", "", "json"),
  ]),
  Endpoint.new("/graphql#Mutation.createUser", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
    Param.new("graphql_mutation_createUser", "", "json"),
  ]),
  Endpoint.new("/graphql#Subscription.userAdded", "POST", [
    Param.new("graphql_subscription_userAdded", "", "json"),
  ]),
]).perform_tests

# Custom root types declared via `schema { query: ..., mutation: ... }`.
FunctionalTester.new("fixtures/specification/graphql_sdl/schema_block/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/graphql#Query.ping", "POST", [
    Param.new("graphql_query_ping", "", "json"),
  ]),
  Endpoint.new("/graphql#Mutation.publish", "POST", [
    Param.new("channel", "", "json"),
    Param.new("body", "", "json"),
  ]),
]).perform_tests

# `extend type Query` / `extend type Mutation` (federation/stitching).
FunctionalTester.new("fixtures/specification/graphql_sdl/extend_federation/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/graphql#Query.searchProducts", "POST", [
    Param.new("q", "", "json"),
  ]),
  Endpoint.new("/graphql#Mutation.addToCart", "POST", [
    Param.new("productId", "", "json"),
    Param.new("quantity", "", "json"),
  ]),
]).perform_tests
