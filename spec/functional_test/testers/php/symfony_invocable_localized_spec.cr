require "../../func_spec.cr"

# Symfony routes a class-level `#[Route]` to `__invoke` when no method of the
# class carries a route, and registers one route per locale for a localized
# `path` map.
expected_endpoints = [
  Endpoint.new("/api/login", "POST", [Param.new("username", "", "form")]),
  Endpoint.new("/api/logout", "POST"),
  Endpoint.new("/site/about-us", "GET"),
  Endpoint.new("/site/over-ons", "GET"),
  Endpoint.new("/site/contact", "GET"),
  Endpoint.new("/site/contact", "POST"),
  Endpoint.new("/site/kontakt", "GET"),
  Endpoint.new("/site/kontakt", "POST"),
  Endpoint.new("/site/page/{page}", "GET", [Param.new("page", "", "path")]),
]

tester = FunctionalTester.new("fixtures/php/symfony_invocable_localized/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Symfony invocable and localized routes", tags: "functional" do
  it "names __invoke as the handler and keeps the class guard" do
    login = tester.app.endpoints.find! { |ep| ep.url == "/api/login" }
    login.handler.not_nil!.name.should eq("LoginController::__invoke")
    login.tags.map(&.name).should_not contain("auth")

    logout = tester.app.endpoints.find! { |ep| ep.url == "/api/logout" }
    logout.handler.not_nil!.name.should eq("LogoutController::__invoke")
    logout.tags.map(&.description).should contain("Protected by Symfony #[IsGranted('ROLE_USER')]")
  end

  it "does not route a class prefix on its own" do
    urls = tester.app.endpoints.map(&.url)
    urls.should_not contain("/site")
    urls.should_not contain("/internal")
  end
end
