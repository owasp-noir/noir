require "../../spec_helper"
require "../../../src/analyzer/engines/java_engine"
require "../../../src/analyzer/analyzers/java/spring"

# `{verb url params filter-served}` of each route the security chain in
# `code` yields.
private def security_routes(code : String) : Array(String)
  Analyzer::Java::JavaEngine.spring_security_routes(Analyzer::Java::JavaEngine.strip_comments(code)).map do |verb, url, params, _, _, served|
    "#{verb} #{url} #{params.join(",")} #{served ? "filter" : "-"}".strip
  end
end

private def chain(body : String) : String
  "class C { SecurityFilterChain c(HttpSecurity http) throws Exception { #{body} return http.build(); } }"
end

describe "Analyzer::Java::JavaEngine.spring_security_routes" do
  it "reads literal and same-file constant URLs" do
    security_routes(chain(%(http.formLogin(f -> f.loginProcessingUrl("/do")).logout(l -> l.logoutUrl("/bye"));)))
      .should eq(["POST /do username,password filter", "POST /bye  filter"])
    security_routes("class C { static final String P = \"/p\"; SecurityFilterChain c(HttpSecurity http) { http.formLogin(f -> f.loginProcessingUrl(P)); return http.build(); } }")
      .should eq(["POST /p username,password filter"])
  end

  it "yields no default route for a URL or matcher it cannot read" do
    security_routes(chain(%(http.formLogin(f -> f.loginPage(Paths.LOGIN).loginProcessingUrl(Paths.PROCESS)).logout(l -> l.logoutUrl(urls.logout()));))).should be_empty
    security_routes(chain(%(http.logout(l -> l.logoutRequestMatcher(new AntPathRequestMatcher("/doLogout", "GET")));))).should eq(["GET /doLogout  filter"])
    security_routes(chain(%(http.logout(l -> l.logoutRequestMatcher(PathPatternRequestMatcher.withDefaults().matcher("/x")));))).should be_empty
  end

  it "counts only configurers of an HttpSecurity chain, honouring disable" do
    security_routes(chain(%(http.logout(AbstractHttpConfigurer::disable).formLogin(f -> f.disable()); tokenService.logout(token); String s = ".logout(x)";))).should be_empty
    security_routes(chain(%(http.authorizeRequests().anyRequest().authenticated().and().formLogin().and().logout();)))
      .should eq(["POST /login username,password filter", "POST /logout  filter"])
  end

  it "reads the Kotlin DSL inside http { }" do
    code = "class S { fun c(http: HttpSecurity): SecurityFilterChain { http { logout { logoutUrl = \"/bye\" } }; return http.build() } fun logout() { svc.logout { } } }"
    security_routes(code).should eq(["POST /bye  filter"])
  end

  it "leaves a route outside its chain's securityMatcher unserved" do
    security_routes(chain(%(http.securityMatcher("/admin/**").formLogin(f -> f.loginProcessingUrl("/admin/login")).logout(l -> l.permitAll());)))
      .should eq(["POST /admin/login username,password filter", "POST /logout  -"])
  end
end

private def actuator_urls(yaml_content : String) : Array(String)
  dir = File.tempname("spring_actuator_probe")
  pom = File.join(dir, "pom.xml")
  cfg = File.join(dir, "src", "main", "resources", "application.yml")
  Dir.mkdir_p(File.dirname(cfg))
  File.write(pom, "<project><dependencies><dependency><artifactId>spring-boot-starter-actuator</artifactId></dependency></dependencies></project>")
  File.write(cfg, yaml_content)
  controller = File.join(dir, "src", "main", "java", "x", "C.java")
  Dir.mkdir_p(File.dirname(controller))
  File.write(controller, "package x;\n@RestController\npublic class C {\n  @GetMapping(\"/items\")\n  public String items() { return \"\"; }\n}\n")
  CodeLocator.instance.clear_all
  {pom, cfg, controller}.each { |file| CodeLocator.instance.register_path(file) }
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  Analyzer::Java::Spring.new(options).analyze.map { |ep| "#{ep.method} #{ep.url}" }.reject("GET /items")
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(dir) if dir && Dir.exists?(dir)
end

describe "Analyzer::Java::JavaEngine#spring_provided_endpoints" do
  it "omits the discovery root when management.endpoints.web.base-path is / or discovery.enabled is false" do
    actuator_urls("management:\n  endpoints:\n    web:\n      base-path: /\n").should eq(["GET /health"])
    actuator_urls("management:\n  endpoints:\n    web:\n      discovery:\n        enabled: false\n").should eq(["GET /actuator/health"])
    actuator_urls("management:\n  endpoints:\n    web:\n      base-path: /actuator\n").should eq(["GET /actuator", "GET /actuator/health"])
    # On its own port the root is not shared with the app, so Boot keeps it.
    actuator_urls("management:\n  server:\n    port: 9001\n  endpoints:\n    web:\n      base-path: /\n").should eq(["GET /", "GET /health"])
  end
end
