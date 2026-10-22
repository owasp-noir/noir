require "../../func_spec.cr"

# Every root field rides on POST /v1/graphql, disambiguated by a URL
# fragment the same way graphql_sdl and OpenRPC do — the optimizer
# dedupes on (method, url), so without the fragment they would all
# collapse into one endpoint.
expected_endpoints = [
  # The permission columns reach the params through the synthesized
  # `movies_bool_exp` input type, which the SDL parser expands into
  # dotted fields rather than a bare `where`.
  Endpoint.new("/v1/graphql#Query.movies", "POST", [
    Param.new("where.id", "", "json"),
    Param.new("where.title", "", "json"),
    Param.new("where.release_year", "", "json"),
    Param.new("limit", "", "json"),
    Param.new("graphql_query_movies", "", "json"),
  ]),
  # movies names an `id` column, so the by-pk fields exist.
  Endpoint.new("/v1/graphql#Query.movies_by_pk", "POST"),
  Endpoint.new("/v1/graphql#Query.movies_aggregate", "POST"),
  Endpoint.new("/v1/graphql#Mutation.insert_movies", "POST"),
  Endpoint.new("/v1/graphql#Mutation.insert_movies_one", "POST"),
  Endpoint.new("/v1/graphql#Mutation.update_movies", "POST"),
  Endpoint.new("/v1/graphql#Mutation.update_movies_by_pk", "POST"),
  Endpoint.new("/v1/graphql#Mutation.delete_movies", "POST"),
  Endpoint.new("/v1/graphql#Mutation.delete_movies_by_pk", "POST"),

  # directors names only `name`, so no primary key is invented for it.
  Endpoint.new("/v1/graphql#Query.directors", "POST"),
  Endpoint.new("/v1/graphql#Query.directors_aggregate", "POST"),
  Endpoint.new("/v1/graphql#Mutation.insert_directors", "POST"),
  Endpoint.new("/v1/graphql#Mutation.insert_directors_one", "POST"),
  Endpoint.new("/v1/graphql#Mutation.update_directors", "POST"),
  Endpoint.new("/v1/graphql#Mutation.delete_directors", "POST"),

  # The only real REST surface is what rest_endpoints.yaml declares.
  Endpoint.new("/api/rest/movie/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/specification/hasura/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
