require "../../func_spec.cr"

# Endpoint is a struct: set the protocol on a local copy.
ws = ->(ep : Endpoint) do
  ep.protocol = "ws"
  ep
end

# FastAPI app: root types bound by `strawberry.Schema(...)` in schema.py,
# fields spread over queries/mutations/subscriptions modules, `Query`
# inheriting `BookQuery`, and the router mounted at `/api/graphql`.
# `tests/` and the strawberry-free `other/` module contribute nothing.
FunctionalTester.new("fixtures/python/strawberry/", {
  :techs     => 2,
  :endpoints => 8,
}, [
  Endpoint.new("/api/graphql#Query.books", "POST", [
    Param.new("authorName", "", "json"),
    Param.new("limit", "", "json"),
    Param.new("graphql_query_books", "query($authorName: String, $limit: Int!) { books(authorName: $authorName, limit: $limit) }", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.book", "POST", [
    Param.new("bookId", "", "json"),
    Param.new("graphql_query_book", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.greeting", "POST", [
    Param.new("graphql_query_greeting", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.serverVersion", "POST", [
    Param.new("graphql_query_serverVersion", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.searchBooks", "POST", [
    Param.new("searchTerm", "", "json"),
    Param.new("maxResults", "", "json"),
    Param.new("graphql_query_searchBooks", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Mutation.addBook", "POST", [
    Param.new("title", "", "json"),
    Param.new("author", "", "json"),
    Param.new("graphql_mutation_addBook", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Mutation.deleteBook", "POST", [
    Param.new("bookId", "", "json"),
    Param.new("graphql_mutation_deleteBook", "", "json"),
  ]),
  ws.call(Endpoint.new("/api/graphql#Subscription.countUp", "POST", [
    Param.new("target", "", "json"),
    Param.new("graphql_subscription_countUp", "", "json"),
  ])),
]).perform_tests

# Django app: `merge_types` root, `auto_camel_case=False`, and the
# `AsyncGraphQLView` mounted at `graphql/`.
FunctionalTester.new("fixtures/python/strawberry_django/", {
  :techs     => 2,
  :endpoints => 4,
}, [
  Endpoint.new("/graphql/#Query.user_by_email", "POST", [
    Param.new("email_address", "", "json"),
    Param.new("graphql_query_user_by_email", "", "json"),
  ]),
  Endpoint.new("/graphql/#Query.recent_posts", "POST", [
    Param.new("graphql_query_recent_posts", "", "json"),
  ]),
  Endpoint.new("/graphql/#Mutation.publish_post", "POST", [
    Param.new("post_id", "", "json"),
    Param.new("graphql_mutation_publish_post", "", "json"),
  ]),
  Endpoint.new("/graphql/", "GET"),
]).perform_tests
