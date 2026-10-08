require "../../func_spec.cr"

# Absinthe code-first schema: root fields from `query`/`mutation`/
# `subscription`, from `import_fields` objects in another module (chained),
# and from `extend object(:mutation)`. Names are camelCased by the default
# LanguageConventions adapter; the Phoenix `forward "/graphql", Absinthe.Plug`
# inside `scope "/api"` sets the mount. The two GET rows are Phoenix's own
# view of the `forward` lines.
FunctionalTester.new("fixtures/elixir/absinthe/", {
  :techs     => 2,
  :endpoints => 11,
}, [
  Endpoint.new("/api/graphql#Query.posts", "POST", [
    Param.new("authorId", "", "json"),
    Param.new("graphql_query_posts", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.user", "POST", [
    Param.new("id", "", "json"),
    Param.new("graphql_query_user", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.me", "POST", [
    Param.new("graphql_query_me", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.searchUsers", "POST", [
    Param.new("namePrefix", "", "json"),
    Param.new("filter", "", "json"),
    Param.new("graphql_query_searchUsers", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.allUsers", "POST", [
    Param.new("graphql_query_allUsers", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Mutation.createPost", "POST", [
    Param.new("title", "", "json"),
    Param.new("publishedAt", "", "json"),
    Param.new("tags", "", "json"),
    Param.new("graphql_mutation_createPost", "", "json"),
  ]),
  # `name: "remove_post"` overrides the identifier, then gets camelCased.
  Endpoint.new("/api/graphql#Mutation.removePost", "POST", [
    Param.new("id", "", "json"),
    Param.new("graphql_mutation_removePost", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Mutation.updateProfile", "POST", [
    Param.new("displayName", "", "json"),
    Param.new("graphql_mutation_updateProfile", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Subscription.newPost", "POST", [
    Param.new("graphql_subscription_newPost", "", "json"),
  ]),
]).perform_tests

# `adapter: Absinthe.Adapter.Passthrough` keeps snake_case names; Plug.Router's
# `forward "/gql", to: Absinthe.Plug` sets the mount. GET /gql is Plug's row.
FunctionalTester.new("fixtures/elixir/absinthe_passthrough/", {
  :techs     => 2,
  :endpoints => 2,
}, [
  Endpoint.new("/gql#Query.list_items", "POST", [
    Param.new("page_size", "", "json"),
    Param.new("graphql_query_list_items", "", "json"),
  ]),
]).perform_tests

# Same shapes without Absinthe: nothing is detected.
FunctionalTester.new("fixtures/elixir/absinthe_negative/", {
  :techs     => 0,
  :endpoints => 0,
}, nil).perform_tests
