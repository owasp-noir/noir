require "../../func_spec.cr"

# A `typeDefs` schema inside `test/yoga.test.ts` is a fixture, not a deployed
# GraphQL endpoint.
FunctionalTester.new("fixtures/javascript/graphql_yoga_test_file/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/graphql#Query.hello", "POST", [
    Param.new("graphql_query_hello", "", "json"),
  ]),
]).perform_tests
