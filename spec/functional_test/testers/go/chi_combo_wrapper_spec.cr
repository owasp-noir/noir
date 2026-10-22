require "../../func_spec.cr"

# gitea's `modules/web` wrapper registers one path with several verbs
# through a `Combo` chain (`m.Combo("/token").Get(h).Delete(h)`) and an
# explicit method list through `Methods("GET, HEAD", "/x", h)`. Neither
# shape is a chi verb call, so before this fixture the 93 Combo chains in
# gitea's API router contributed nothing.
expected_endpoints = [
  Endpoint.new("/robots.txt", "GET"),
  Endpoint.new("/robots.txt", "HEAD"),
  Endpoint.new("/assets/*", "GET"),
  Endpoint.new("/assets/*", "HEAD"),
  Endpoint.new("/assets/*", "OPTIONS"),
  Endpoint.new("/user/token", "GET"),
  Endpoint.new("/user/token", "DELETE"),
  Endpoint.new("/user/actions/secrets", "GET"),
  Endpoint.new("/user/actions/secrets/{secretname}", "GET"),
  Endpoint.new("/user/actions/secrets/{secretname}", "PUT"),
  Endpoint.new("/user/actions/secrets/{secretname}", "DELETE"),
]

tester = FunctionalTester.new("fixtures/go/chi_combo_wrapper/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

# The wrapper's verbs take `middleware..., handler`: the handler is the last
# argument, not the `reqToken()` in front of it.
it "names the last argument of a wrapper verb as its handler", tags: "functional" do
  api_go = "./spec/functional_test/fixtures/go/chi_combo_wrapper/routers/api.go"
  list = tester.app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/user/actions/secrets" }
  list.handler.should eq(Handler.new("listSecrets", api_go, 18))
  token = tester.app.endpoints.find! { |ep| ep.method == "DELETE" && ep.url == "/user/token" }
  token.handler.should eq(Handler.new("deleteToken", api_go, 14))
end
