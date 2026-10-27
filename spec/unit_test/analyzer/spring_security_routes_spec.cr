require "../../spec_helper"
require "../../../src/analyzer/engines/java_engine"

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
