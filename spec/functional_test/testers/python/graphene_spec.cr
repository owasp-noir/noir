require "../../func_spec.cr"

# Endpoint is a struct: set the protocol on a local copy.
ws = ->(ep : Endpoint) do
  ep.protocol = "ws"
  ep
end

# graphene-django cookbook layout: the project `Query` / `Mutation` inherit
# each app's (`cookbook.ingredients.schema.Query`, an aliased
# `recipes_schema.Query`), mutations take `class Arguments` or a relay
# `input`, and the view is mounted at `api/graphql/`. The unbound
# `Unused` type and the graphene-free `legacy/` module contribute nothing.
FunctionalTester.new("fixtures/python/graphene/", {
  :techs     => 2,
  :endpoints => 11,
}, [
  Endpoint.new("/api/graphql/#Query.category", "POST", [
    Param.new("id", "", "json"),
    Param.new("name", "", "json"),
    Param.new("graphql_query_category", "query($id: Int, $name: String) { category(id: $id, name: $name) }", "json"),
  ]),
  Endpoint.new("/api/graphql/#Query.allCategories", "POST", [
    Param.new("graphql_query_allCategories", "", "json"),
  ]),
  Endpoint.new("/api/graphql/#Query.allIngredients", "POST", [
    Param.new("before", "", "json"),
    Param.new("after", "", "json"),
    Param.new("first", "", "json"),
    Param.new("last", "", "json"),
    Param.new("offset", "", "json"),
  ]),
  Endpoint.new("/api/graphql/#Query.recipe", "POST", [
    Param.new("recipeId", "", "json"),
    Param.new("includeDrafts", "", "json"),
  ]),
  Endpoint.new("/api/graphql/#Query.allRecipes", "POST", [
    Param.new("first", "", "json"),
  ]),
  Endpoint.new("/api/graphql/#Query.hello", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/api/graphql/#Query.node", "POST", [
    Param.new("id", "", "json"),
  ]),
  Endpoint.new("/api/graphql/#Mutation.createCategory", "POST", [
    Param.new("name", "", "json"),
    Param.new("parentId", "", "json"),
    Param.new("graphql_mutation_createCategory", "mutation($name: String!, $parentId: ID) { createCategory(name: $name, parentId: $parentId) }", "json"),
  ]),
  Endpoint.new("/api/graphql/#Mutation.updateIngredient", "POST", [
    Param.new("input", "", "json"),
  ]),
  ws.call(Endpoint.new("/api/graphql/#Subscription.countSeconds", "POST", [
    Param.new("upTo", "", "json"),
  ])),
  Endpoint.new("/api/graphql/", "GET"),
]).perform_tests

# Saleor-style: the root types are composed in a module that never imports
# graphene and handed to a project helper rather than `graphene.Schema`, so
# the canonical root names bind. `doc_category=` is an app option, not an
# argument, and the graphene-free `Subscription(ObjectType)` stays out.
FunctionalTester.new("fixtures/python/graphene_composed/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/graphql#Query.product", "POST", [
    Param.new("slug", "", "json"),
    Param.new("graphql_query_product", "query($slug: String!) { product(slug: $slug) }", "json"),
  ]),
  Endpoint.new("/graphql#Mutation.reindexProducts", "POST", [
    Param.new("force", "", "json"),
  ]),
]).perform_tests
