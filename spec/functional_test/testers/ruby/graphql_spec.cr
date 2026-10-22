require "../../func_spec.cr"

# graphql-ruby code-first schema: `AppSchema < GraphQL::Schema` binds the
# three roots; fields come from the root classes, an included concern, the
# Relay `HasNodeField` mixin, a `resolver:` class and `mutation:` classes.
# Names are camelized unless `camelize: false`; the mount comes from the
# Rails route to `graphql#execute`, which the Rails analyzer also reports.
FunctionalTester.new("fixtures/ruby/graphql/", {
  :techs     => 2,
  :endpoints => 11,
}, [
  Endpoint.new("/api/graphql#Query.post", "POST", [
    Param.new("id", "", "json"),
    Param.new("graphql_query_post", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.posts", "POST", [
    Param.new("authorId", "", "json"),
    Param.new("order_by", "", "json"),
    Param.new("graphql_query_posts", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.postsConnection", "POST", [
    Param.new("after", "", "json"),
    Param.new("before", "", "json"),
    Param.new("first", "", "json"),
    Param.new("last", "", "json"),
    Param.new("graphql_query_postsConnection", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.viewer_name", "POST", [
    Param.new("graphql_query_viewer_name", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.search", "POST", [
    Param.new("term", "", "json"),
    Param.new("maxResults", "", "json"),
    Param.new("graphql_query_search", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.node", "POST", [
    Param.new("id", "", "json"),
    Param.new("graphql_query_node", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Query.currentUser", "POST", [
    Param.new("graphql_query_currentUser", "", "json"),
  ]),
  # RelayClassicMutation (via BaseMutation) wraps its arguments in `input`.
  Endpoint.new("/api/graphql#Mutation.createPost", "POST", [
    Param.new("input", "", "json"),
    Param.new("graphql_mutation_createPost", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Mutation.deletePost", "POST", [
    Param.new("postId", "", "json"),
    Param.new("graphql_mutation_deletePost", "", "json"),
  ]),
  Endpoint.new("/api/graphql#Subscription.postAdded", "POST", [
    Param.new("roomId", "", "json"),
    Param.new("graphql_subscription_postAdded", "", "json"),
  ]),
  Endpoint.new("/api/graphql", "POST"),
]).perform_tests

# graphql-client usage (no `GraphQL::Schema` subclass) is not a server.
FunctionalTester.new("fixtures/ruby/graphql_negative/", {
  :techs     => 0,
  :endpoints => 0,
}, [] of Endpoint).perform_tests
