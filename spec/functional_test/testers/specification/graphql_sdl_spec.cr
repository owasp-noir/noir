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
    Param.new("graphql_mutation_publish", "", "json"),
  ]),
]).perform_tests

# `extend type Query` / `extend type Mutation` (federation/stitching).
FunctionalTester.new("fixtures/specification/graphql_sdl/extend_federation/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/graphql#Query.searchProducts", "POST", [
    Param.new("q", "", "json"),
    Param.new("graphql_query_searchProducts", "", "json"),
  ]),
  Endpoint.new("/graphql#Mutation.addToCart", "POST", [
    Param.new("productId", "", "json"),
    Param.new("quantity", "", "json"),
    Param.new("graphql_mutation_addToCart", "", "json"),
  ]),
]).perform_tests

# One schema split across a directory: `schema.graphql` names the custom
# roots and declares `PageInput`; the root types and the fields that take it
# live in the other files. `orders.graphql` has no `schema` block of its own
# and keeps its `extend type Query`.
FunctionalTester.new("fixtures/specification/graphql_sdl/split/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/graphql#Query.users", "POST", [
    Param.new("page.first", "", "json"),
    Param.new("page.after", "", "json"),
    Param.new("graphql_query_users", "", "json"),
  ]),
  Endpoint.new("/graphql#Mutation.createUser", "POST", [
    Param.new("name", "", "json"),
    Param.new("graphql_mutation_createUser", "", "json"),
  ]),
  Endpoint.new("/graphql#Query.orders", "POST", [
    Param.new("page.first", "", "json"),
    Param.new("page.after", "", "json"),
    Param.new("graphql_query_orders", "", "json"),
  ]),
]).perform_tests
