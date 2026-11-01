require "../../func_spec.cr"

# Handler bodies are read off the syntax tree: a `{` in a return type, a
# template literal, a regex or an unrelated sibling function never moves a
# body boundary.

def callee_endpoint(url : String, method : String, params : Array(Param), callees : Array(Tuple(String, Int32))) : Endpoint
  endpoint = Endpoint.new(url, method, params)
  callees.each { |name, line| endpoint.push_callee(Callee.new(name, line: line)) }
  endpoint
end

# Vercel: object-literal return types, `satisfies`, overloads.
FunctionalTester.new("fixtures/javascript/vercel_body_ast/", {
  :techs     => 1,
  :endpoints => 6,
}, [
  callee_endpoint("/api/typed", "GET", [Param.new("page", "", "query")], [{"loadTyped", 8}]),
  callee_endpoint("/api/typed", "POST", [Param.new("title", "", "json")], [{"loadTyped", 13}]),
  callee_endpoint("/api/literals", "ANY", [Param.new("x-literal-token", "", "header"), Param.new("after", "", "query")], [{"render", 12}]),
  callee_endpoint("/api/satisfies", "PUT", [Param.new("name", "", "json")], [{"save", 8}]),
  callee_endpoint("/api/satisfies", "DELETE", [Param.new("id", "", "query")], [{"save", 11}]),
  callee_endpoint("/api/overloads", "GET", [Param.new("filter", "", "query")], [{"lookup", 8}]),
], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests

# Next.js app router, pages router and server actions.
FunctionalTester.new("fixtures/javascript/nextjs_body_ast/", {
  :techs     => 1,
  :endpoints => 15,
}, [
  callee_endpoint("/api/typed", "GET", [Param.new("page", "", "query")], [{"loadTyped", 6}]),
  callee_endpoint("/api/typed", "POST", [Param.new("title", "", "json")], [{"loadTyped", 11}]),
  callee_endpoint("/api/tmpl", "GET", [Param.new("x-tmpl-token", "", "header")], [{"render", 8}]),
  callee_endpoint("/api/tmpl", "DELETE", [Param.new("id", "", "query")], [{"render", 13}]),
  callee_endpoint("/api/nest", "GET", [Param.new("q", "", "query")], [{"renderCard", 10}, {"inner", 10}]),
  callee_endpoint("/api/over", "GET", [Param.new("filter", "", "query")], [{"lookup", 8}]),
  callee_endpoint("/api/wrap", "GET", [Param.new("limit", "", "query")], [{"listWrapped", 7}]),
  callee_endpoint("/api/paged", "GET", [Param.new("page", "", "query")], [{"loadTyped", 9}]),
  # `currentId` is expression-bodied: the `{` after it is `login`'s.
  callee_endpoint("/currentId", "POST", [] of Param, [] of Tuple(String, Int32)),
  callee_endpoint("/login", "POST", [Param.new("email", "", "form")], [{"createUser", 13}]),
], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests

# Fresh handler objects whose methods carry return types.
FunctionalTester.new("fixtures/javascript/fresh_body_ast/", {
  :techs     => 1,
  :endpoints => 7,
}, [
  callee_endpoint("/api/typed", "GET", [] of Param, [{"loadThing", 6}]),
  callee_endpoint("/api/typed", "POST", [] of Param, [{"saveThing", 11}]),
  callee_endpoint("/api/single", "GET", [] of Param, [{"runAll", 4}]),
], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests

# TanStack Router config slots: a typed `loader` is walked, and `async`
# is not mistaken for a component reference.
FunctionalTester.new("fixtures/typescript/tanstack_body_ast/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  callee_endpoint("/posts", "GET", [] of Param, [{"PostsPage", 5}, {"fetchPosts", 8}]),
], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
