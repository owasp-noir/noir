require "../../func_spec.cr"

article_endpoint = Endpoint.new("/api/graphql#Query.article", "POST", [
  Param.new("id", "", "json"),
  Param.new("graphql_query_article", "query($id: String) { article(id: $id) }", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("articleService.findArticle", line: 13))
end

create_endpoint = Endpoint.new("/api/graphql#Mutation.createArticle", "POST", [
  Param.new("title", "", "json"),
  Param.new("graphql_mutation_createArticle", "mutation($input: CreateArticleInput) { createArticle(input: $input) }", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("articleService.createArticle", line: 18))
end

comment_endpoint = Endpoint.new("/api/graphql#Mutation.addComment", "POST", [
  Param.new("articleId", "", "json"),
  Param.new("body", "", "json"),
  Param.new("graphql_mutation_addComment", "mutation($articleId: String, $input: CommentInput) { addComment(articleId: $articleId, input: $input) }", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("articleService.addComment", line: 23))
end

tagged_article_endpoint = Endpoint.new("/api/graphql#Mutation.createTaggedArticle", "POST", [
  Param.new("tags.label", "", "json"),
  Param.new("graphql_mutation_createTaggedArticle", "mutation($tags: List<TagInput>) { createTaggedArticle(tags: $tags) }", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("articleService.createTaggedArticle", line: 28))
end

author_endpoint = Endpoint.new("/api/graphql#Article.author", "POST", [
  Param.new("graphql_field_author", "field Article.author", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("articleService.findAuthor", line: 33))
end

comments_endpoint = Endpoint.new("/api/graphql#Article.comments", "POST", [
  Param.new("graphql_field_comments", "field Article.comments", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("articleService.findComments", line: 38))
end

summary_endpoint = Endpoint.new("/api/graphql#Article.summary", "POST", [
  Param.new("graphql_field_summary", "field Article.summary", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("summaryService.buildSummary", line: 10))
end

ping_endpoint = Endpoint.new("/api/graphql#Query.ping", "POST", [
  Param.new("graphql_query_ping", "query { ping }", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("GraphqlController.ping", line: 41))
end

expected_endpoints = [
  article_endpoint,
  create_endpoint,
  comment_endpoint,
  tagged_article_endpoint,
  author_endpoint,
  comments_endpoint,
  summary_endpoint,
  ping_endpoint,
]

FunctionalTester.new("fixtures/kotlin/spring_graphql/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
