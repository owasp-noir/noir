require "../../func_spec.cr"

root = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("response.render"))
  ep.push_callee(Callee.new("HomePage.render"))
end

health = Endpoint.new("/api/health", "GET").tap do |ep|
  ep.push_callee(Callee.new("response.render"))
  ep.push_callee(Callee.new("HealthCheck.ready"))
end

interpolated = Endpoint.new("/{API_PREFIX}/items", "GET", [
  Param.new("API_PREFIX", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("response.render"))
  ep.push_callee(Callee.new("HealthCheck.ready"))
end

secure = Endpoint.new("/secure", "GET", [
  Param.new("Authorization", "", "header"),
]).tap do |ep|
  ep.push_callee(Callee.new("response.render"))
  ep.push_callee(Callee.new("SecureRenderer.render"))
  ep.push_callee(Callee.new("TokenVerifier.verify"))
end

block_inline = Endpoint.new("/block/inline", "GET")

block_after = Endpoint.new("/block/after", "GET").tap do |ep|
  ep.push_callee(Callee.new("response.render"))
  ep.push_callee(Callee.new("HealthCheck.ready"))
end

cafe_show = Endpoint.new("/cafes/:id", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("CafeRepo.find"))
end

review_new = Endpoint.new("/cafes/:cafe_id/reviews/new", "GET", [
  Param.new("cafe_id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("ReviewForm.build"))
end

review_create = Endpoint.new("/cafes/:cafe_id/reviews", "POST", [
  Param.new("cafe_id", "", "path"),
  Param.new("content", "", "json"),
  Param.new("rating", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("CreateReview.call"))
end

account_show = Endpoint.new("/account", "GET").tap do |ep|
  ep.push_callee(Callee.new("response.render"))
  ep.push_callee(Callee.new("actor"))
end

users_create = Endpoint.new("/users", "POST", [
  Param.new("user", "", "json"),
  Param.new("username", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserRepository.create"))
end

users_login = Endpoint.new("/users/login", "POST").tap do |ep|
  ep.push_callee(Callee.new("Authenticator.login"))
end

article_show = Endpoint.new("/articles/:slug", "GET", [
  Param.new("slug", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("ArticleRepository.find_by_slug"))
end

widgets_build = Endpoint.new("/widgets/:id/build", "POST", [
  Param.new("id", "", "path"),
  Param.new("quantity", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("response.render"))
  ep.push_callee(Callee.new("request.params"))
end

sidekiq = Endpoint.new("/sidekiq", "GET")

expected_endpoints = [
  root,
  interpolated,
  secure,
  health,
  block_inline,
  block_after,
  cafe_show,
  review_new,
  review_create,
  account_show,
  users_create,
  users_login,
  article_show,
  widgets_build,
  sidekiq,
]

FunctionalTester.new("fixtures/ruby/hanami_advanced/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
