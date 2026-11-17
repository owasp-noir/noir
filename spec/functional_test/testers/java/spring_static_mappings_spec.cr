require "../../func_spec.cr"

# Which URL a static file answers on is decided by the resource handlers of
# its module, and Boot's `/**` over `static/` is only the default one:
#
#   * webmvc:     `@EnableWebMvc` replaces Boot's web auto-configuration, so
#                 only the registered `/assets/**` handler serves `static/`;
#   * nomappings: `spring.web.resources.add-mappings=false` turns the
#                 default handler off;
#   * pattern:    `spring.mvc.static-path-pattern` moves the default handler;
#   * additive:   a handler registered without `@EnableWebMvc` serves its
#                 own location next to the default one;
#   * mixed:      the `@EnableWebMvc` configuration of a Java module is a
#                 Kotlin class.
expected_endpoints = [
  Endpoint.new("/assets/**", "GET"),
  Endpoint.new("/assets/app.js", "GET"),
  Endpoint.new("/nomappings/ping", "GET"),
  Endpoint.new("/pattern/ping", "GET"),
  Endpoint.new("/content/logo.txt", "GET"),
  Endpoint.new("/files/**", "GET"),
  Endpoint.new("/files/guide.txt", "GET"),
  Endpoint.new("/index.html", "GET"),
  Endpoint.new("/mixed/ping", "GET"),
  Endpoint.new("/home.txt", "GET"),
]

tester = FunctionalTester.new("fixtures/java/spring_static_mappings/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Spring static resource mappings", tags: "functional" do
  it "serves a file only where a resource handler maps it" do
    tester.endpoints.map(&.url).sort!.should eq(expected_endpoints.map(&.url).sort!)
  end
end
