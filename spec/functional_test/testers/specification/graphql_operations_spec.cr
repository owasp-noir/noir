require "../../func_spec.cr"

# Operation documents shipped as a `.gql` file (not SDL) are the
# `graphql_operation` technology: one `POST <base>/graphql` endpoint carrying
# one param per named top-level operation (the optimizer dedupes on
# method + url), so both the query and the mutation here surface on one
# endpoint.
#
# `:techs => 1` is the point of the change that introduced this technology.
# These documents used to be read by a `FileAnalyzer` hook that ran outside
# the tech registry: the fixture detected *zero* technologies, the endpoint
# came out with `"technology": null`, and every `--only-techs <T>` run
# returned it on top of whatever T produced.
FunctionalTester.new("fixtures/specification/graphql_operations/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("https://ex.com/graphql", "POST", [
    Param.new("graphql_operation_query_GetUser", "", "json"),
    Param.new("graphql_operation_mutation_CreateUser", "", "json"),
  ]),
], {"url" => YAML::Any.new("https://ex.com")}).perform_tests

# ...and they are found on a plain `noir scan ./app` too. `-u/--url` only
# prefixes the discovered paths; it is not what makes the documents visible.
FunctionalTester.new("fixtures/specification/graphql_operations/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/graphql", "POST", [
    Param.new("graphql_operation_query_GetUser", "", "json"),
    Param.new("graphql_operation_mutation_CreateUser", "", "json"),
  ]),
]).perform_tests
