require "../../func_spec.cr"

# Implementation-first HotChocolate: roots registered with AddQueryType<T>()
# and friends, [ExtendObjectType] extensions, source-generator [QueryType] /
# [MutationType] classes, mutation conventions and a custom MapGraphQL path.
FunctionalTester.new("fixtures/csharp/hotchocolate/", {
  :techs     => 1,
  :endpoints => 19,
}, [
  # AddGlobalObjectIdentification() adds the Relay node fields.
  Endpoint.new("/api/graphql#Query.node", "POST", [
    Param.new("id", "", "json"),
    Param.new("graphql_query_node", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.nodes", "POST", [
    Param.new("ids", "", "json"),
    Param.new("graphql_query_nodes", "", "json"),
  ]),
  # [Subscribe(With = ...)]: the stream method is excluded.
  Endpoint.new("/api/graphql#Subscription.onReview", "POST", [
    Param.new("graphql_subscription_onReview", "", "json"),
  ]),
  # Member-level [Query] in a plain static class.
  Endpoint.new("/api/graphql#Query.health", "POST", [
    Param.new("graphql_query_health", "", "json"),
  ]),
  # Get prefix dropped; the IBookRepository parameter is injected.
  Endpoint.new("/api/graphql#Query.book", "POST", [
    Param.new("id", "", "json"),
    Param.new("graphql_query_book", "", "json"),
  ]),
  # Async suffix dropped; [UsePaging]/[UseFiltering] add their arguments.
  Endpoint.new("/api/graphql#Query.books", "POST", [
    Param.new("title", "", "json"),
    Param.new("first", "", "json"),
    Param.new("after", "", "json"),
    Param.new("last", "", "json"),
    Param.new("before", "", "json"),
    Param.new("where", "", "json"),
    Param.new("graphql_query_books", "", "json"),
  ]),
  # [GraphQLName] on the method and on the parameter.
  Endpoint.new("/api/graphql#Query.whoAmI", "POST", [
    Param.new("verbose", "", "json"),
    Param.new("graphql_query_whoAmI", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.version", "POST", [
    Param.new("graphql_query_version", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.apiStatus", "POST", [
    Param.new("graphql_query_apiStatus", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.authorById", "POST", [
    Param.new("authorId", "", "json"),
    Param.new("graphql_query_authorById", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.authors", "POST", [
    Param.new("graphql_query_authors", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.authorByName", "POST", [
    Param.new("name", "", "json"),
    Param.new("graphql_query_authorByName", "", "json"),
  ]),
  # AddMutationConventions() folds arguments into one `input`.
  Endpoint.new("/api/graphql#Mutation.addBook", "POST", [
    Param.new("input", "", "json"),
    Param.new("graphql_mutation_addBook", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Mutation.updateBook", "POST", [
    Param.new("input", "", "json"),
    Param.new("graphql_mutation_updateBook", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Mutation.clearCache", "POST", [
    Param.new("graphql_mutation_clearCache", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Mutation.renameAuthor", "POST", [
    Param.new("input", "", "json"),
    Param.new("graphql_mutation_renameAuthor", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Mutation.uploadPhoto", "POST", [
    Param.new("input", "", "json"),
    Param.new("graphql_mutation_uploadPhoto", "", "json"),
  ]),
  # [EventMessage] payloads are not arguments.
  Endpoint.new("/api/graphql#Subscription.onBookAdded", "POST", [
    Param.new("graphql_subscription_onBookAdded", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Subscription.onAuthorBookAdded", "POST", [
    Param.new("authorId", "", "json"),
    Param.new("graphql_subscription_onAuthorBookAdded", "", "json"),
  ]),
]).perform_tests

# Descriptor-first ObjectType<T>: the runtime type's members minus Ignore(),
# literal Field("hello") fields, and BindFieldsExplicitly().
FunctionalTester.new("fixtures/csharp/hotchocolate_descriptor/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/graphql#Query.book", "POST", [
    Param.new("id", "", "json"),
    Param.new("graphql_query_book", "", "json"),
  ]),
  Endpoint.new("/graphql#Query.hello", "POST", [
    Param.new("name", "", "json"),
    Param.new("graphql_query_hello", "", "json"),
  ]),
  Endpoint.new("/graphql#Mutation.ping", "POST", [
    Param.new("graphql_mutation_ping", "", "json"),
  ]),
]).perform_tests

# A plain class named Query without HotChocolate yields nothing.
FunctionalTester.new("fixtures/csharp/hotchocolate_negative/", {
  :techs     => 0,
  :endpoints => 0,
}, [] of Endpoint).perform_tests
