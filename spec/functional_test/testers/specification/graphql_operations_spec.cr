require "../../func_spec.cr"

# Operation documents shipped as a `.gql` file (not SDL) are picked up by
# the file analyzer the same way `.graphql` operation documents are. Every
# named top-level operation rides on a single `POST <base>/graphql`
# endpoint (the optimizer dedupes on method + url), so both the query and
# the mutation here surface as params on one endpoint.
FunctionalTester.new("fixtures/specification/graphql_operations/", {
  :techs     => 0,
  :endpoints => 1,
}, [
  Endpoint.new("https://ex.com/graphql", "POST", [
    Param.new("graphql_operation_query_GetUser", "", "json"),
    Param.new("graphql_operation_mutation_CreateUser", "", "json"),
  ]),
], {"url" => YAML::Any.new("https://ex.com")}).perform_tests
