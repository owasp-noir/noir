require "../../func_spec.cr"

# Apollo Server v4 standalone: 2 Query + 2 Mutation + 1 Subscription = 5 endpoints.
# typeDefs is an inline `gql\`...\`` template literal; the path defaults to /graphql.
FunctionalTester.new("fixtures/javascript/apollo/", {
  :techs     => 1,
  :endpoints => 5,
}, [
  Endpoint.new("/graphql#Query.user", "POST", [
    Param.new("id", "", "json"),
    Param.new("graphql_query_user", "", "json"),
  ]),
  Endpoint.new("/graphql#Query.users", "POST", [
    Param.new("limit", "", "json"),
    Param.new("offset", "", "json"),
    Param.new("graphql_query_users", "", "json"),
  ]),
  Endpoint.new("/graphql#Mutation.createUser", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
    Param.new("graphql_mutation_createUser", "", "json"),
  ]),
  Endpoint.new("/graphql#Mutation.deleteUser", "POST", [
    Param.new("id", "", "json"),
    Param.new("graphql_mutation_deleteUser", "", "json"),
  ]),
  Endpoint.new("/graphql#Subscription.userAdded", "POST", [
    Param.new("graphql_subscription_userAdded", "", "json"),
  ]),
]).perform_tests

# Apollo Server mounted via Express middleware — mount path overrides the default.
# typeDefs uses a plain backtick template literal with a leading `#graphql` marker.
FunctionalTester.new("fixtures/javascript/apollo_express/", {
  :techs     => 2,
  :endpoints => 3,
}, [
  Endpoint.new("/api/graphql#Query.ping", "POST", [
    Param.new("graphql_query_ping", "", "json"),
  ]),
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
