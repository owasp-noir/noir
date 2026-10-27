require "../../func_spec.cr"

# Routes Spring Boot and Spring Security serve with no controller behind
# them (#3092) and the static-resource surface (#3093):
#
#   * Actuator and springdoc come from their dependency in `pom.xml`, with
#     paths and exposure read from `application.yml` (a version pin under
#     `<dependencyManagement>` is not a dependency);
#   * `formLogin` / `logout` / `oauth2Login` in a security chain yield the
#     filter endpoints with their configured URLs and parameter names;
#   * a YAML-list `static-locations` replaces Boot's defaults, and dotfiles
#     under a served directory are served too;
#   * `addResourceHandler(String[] constant)` expands the array.
expected_endpoints = [
  Endpoint.new("/ping", "GET"),
  Endpoint.new("/humans.txt", "GET"),
  Endpoint.new("/icon.ico", "GET"),
  Endpoint.new("/robots.txt", "GET"),
  Endpoint.new("/.env.prod", "GET"),
  Endpoint.new("/.well-known/security.txt", "GET"),
  Endpoint.new("/lily.txt", "GET"),
  Endpoint.new("/actuator", "GET"),
  Endpoint.new("/actuator/health", "GET"),
  Endpoint.new("/actuator/info", "GET"),
  Endpoint.new("/actuator/env", "GET"),
  Endpoint.new("/internal/openapi", "GET"),
  Endpoint.new("/docs-ui.html", "GET"),
  Endpoint.new("/signin/do", "POST", [
    Param.new("handle", "", "form"),
    Param.new("secret", "", "form"),
  ]),
  Endpoint.new("/signout", "POST"),
  Endpoint.new("/oauth2/authorization/{registrationId}", "GET"),
  Endpoint.new("/sso/callback/{registrationId}", "GET", [
    Param.new("code", "", "query"),
    Param.new("state", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/java/spring_provided_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Spring framework-provided routes", tags: "functional" do
  it "tags them apart from controller and static routes" do
    tagged = tester.endpoints.select(&.tags.any? { |tag| tag.name == "framework-provided" }).map(&.url)
    tagged.sort.should eq([
      "/actuator", "/actuator/env", "/actuator/health", "/actuator/info",
      "/docs-ui.html", "/internal/openapi",
      "/oauth2/authorization/{registrationId}", "/signin/do", "/signout",
      "/sso/callback/{registrationId}",
    ])
  end

  it "points the logout route at its LogoutSuccessHandler" do
    handler = tester.endpoints.find!(&.url.==("/signout")).handler.not_nil!
    handler.name.should eq("SignoutHandler.onLogoutSuccess")
    handler.path.not_nil!.should end_with("com/example/SignoutHandler.java")
    handler.line.should eq(10)
  end
end
