require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Fixture line references
#
# spring_security/src/main/java/com/example/SecurityConfig.java
#   14: .csrf(csrf -> csrf.disable())   (global — no securityMatcher)
#
# spring_security/src/main/java/com/example/ApiController.java
#    7: @CrossOrigin(origins = "*")     (class-level, wildcard)
#   12:     public String createPost(@Valid @RequestBody PostDto dto) {
#   17:     public String updatePost(@PathVariable Long id, @RequestBody PostDto dto) {
#   22:     public String listPosts() {
#
# spring_security_scoped/src/main/java/com/example/SecurityConfig.java
#   chain apiChain: securityMatcher("/api/**") + csrf().disable()
#   chain webChain: securityMatcher("/web/**"), CSRF left enabled
#
# spring_security_extras/src/main/java/com/example/
#   SecurityConfig.java   csrf ignoringRequestMatchers("/api/webhook/**")
#                         + headers().frameOptions().disable() (global)
#   CorsConfig.java       addMapping("/api/**").allowedOrigins("*").allowCredentials(true)
#   WebhookController.java  10: POST /api/webhook/github
#   AdminController.java    10: POST /admin/users

private def tag_named(endpoint : Endpoint, name : String) : Tag?
  endpoint.tags.find { |t| t.name == name }
end

private def load_fixture_files(fixture_base : String)
  locator = CodeLocator.instance
  Dir.glob("#{fixture_base}/**/*").each do |file|
    next if File.directory?(file)
    locator.register_path(file)
  end
end

private def build_endpoint(path : String, line : Int32?, url : String, method : String) : Endpoint
  details = line ? Details.new(PathInfo.new(path, line)) : Details.new
  details.technology = "java_spring"
  Endpoint.new(url, method, [] of Param, details)
end

describe "SpringSecurityTagger" do
  global_base = File.expand_path("../../../functional_test/fixtures/java/spring_security", __DIR__)
  controller = "#{global_base}/src/main/java/com/example/ApiController.java"

  scoped_base = File.expand_path("../../../functional_test/fixtures/java/spring_security_scoped", __DIR__)

  global_options = create_test_options
  global_options["base"] = YAML::Any.new(global_base)

  scoped_options = create_test_options
  scoped_options["base"] = YAML::Any.new(scoped_base)

  extras_base = File.expand_path("../../../functional_test/fixtures/java/spring_security_extras", __DIR__)
  webhook_ctrl = "#{extras_base}/src/main/java/com/example/WebhookController.java"
  admin_ctrl = "#{extras_base}/src/main/java/com/example/AdminController.java"

  extras_options = create_test_options
  extras_options["base"] = YAML::Any.new(extras_base)

  before_each do
    CodeLocator.instance.clear_all
  end

  it "exposes java_spring and kotlin_spring as its target techs" do
    SpringSecurityTagger.target_techs.should eq(["java_spring", "kotlin_spring"])
  end

  describe "csrf-protection" do
    it "flags a state-changing endpoint when CSRF is disabled globally" do
      load_fixture_files(global_base)
      endpoint = build_endpoint(controller, 12, "/api/posts", "POST")
      SpringSecurityTagger.new(global_options).perform([endpoint])

      tag = tag_named(endpoint, "csrf-protection")
      tag.should_not be_nil
      tag.not_nil!.tagger.should eq("spring_security")
      tag.not_nil!.description.should contain("globally")
    end

    it "skips an outbound @HttpExchange / Feign declaration (internal)" do
      load_fixture_files(global_base)
      endpoint = build_endpoint(controller, 12, "/api/posts", "POST")
      endpoint.internal = true
      SpringSecurityTagger.new(global_options).perform([endpoint])

      endpoint.tags.should be_empty
    end

    it "flags PUT as well as POST" do
      load_fixture_files(global_base)
      endpoint = build_endpoint(controller, 17, "/api/posts/1", "PUT")
      SpringSecurityTagger.new(global_options).perform([endpoint])

      tag_named(endpoint, "csrf-protection").should_not be_nil
    end

    it "does not flag a GET endpoint (CSRF protection only guards state-changing requests)" do
      load_fixture_files(global_base)
      endpoint = build_endpoint(controller, 22, "/api/posts", "GET")
      SpringSecurityTagger.new(global_options).perform([endpoint])

      tag_named(endpoint, "csrf-protection").should be_nil
    end

    it "scopes a securityMatcher-bound csrf disable to the matched URLs only" do
      load_fixture_files(scoped_base)

      in_scope = build_endpoint(controller, nil, "/api/posts", "POST")
      SpringSecurityTagger.new(scoped_options).perform([in_scope])
      scoped_tag = tag_named(in_scope, "csrf-protection")
      scoped_tag.should_not be_nil
      scoped_tag.not_nil!.description.should contain("/api/**")

      # /web/** keeps CSRF enabled — the disable in apiChain must not leak.
      out_of_scope = build_endpoint(controller, nil, "/web/login", "POST")
      SpringSecurityTagger.new(scoped_options).perform([out_of_scope])
      tag_named(out_of_scope, "csrf-protection").should be_nil
    end
  end

  describe "cors" do
    it "flags a class-level @CrossOrigin wildcard as permissive" do
      load_fixture_files(global_base)
      endpoint = build_endpoint(controller, 12, "/api/posts", "POST")
      SpringSecurityTagger.new(global_options).perform([endpoint])

      tag = tag_named(endpoint, "cors")
      tag.should_not be_nil
      tag.not_nil!.tagger.should eq("spring_security")
      tag.not_nil!.description.should contain("Permissive")
      tag.not_nil!.description.should contain("controller")
    end
  end

  describe "input-validation" do
    it "flags a handler whose body is @Valid-annotated" do
      load_fixture_files(global_base)
      endpoint = build_endpoint(controller, 12, "/api/posts", "POST")
      SpringSecurityTagger.new(global_options).perform([endpoint])

      tag = tag_named(endpoint, "input-validation")
      tag.should_not be_nil
      tag.not_nil!.description.should contain("Bean Validation")
    end

    it "does not flag a handler taking a @RequestBody without @Valid" do
      load_fixture_files(global_base)
      endpoint = build_endpoint(controller, 17, "/api/posts/1", "PUT")
      SpringSecurityTagger.new(global_options).perform([endpoint])

      tag_named(endpoint, "input-validation").should be_nil
    end

    it "does not apply class-level @Validated to handlers without parameters" do
      source = <<-JAVA
        package com.example;
        import org.springframework.validation.annotation.Validated;
        import org.springframework.web.bind.annotation.GetMapping;
        import org.springframework.web.bind.annotation.RestController;

        @Validated
        @RestController
        public class ValidatedController {
          @GetMapping("/health")
          public String health() {
            return "ok";
          }
        }
        JAVA

      path = File.join(Dir.tempdir, "ValidatedController-#{Process.pid}-#{Time.utc.to_unix_ms}.java")
      begin
        File.write(path, source)
        CodeLocator.instance.register_path(path)
        endpoint = build_endpoint(path, 9, "/health", "GET")

        SpringSecurityTagger.new(global_options).perform([endpoint])

        tag_named(endpoint, "input-validation").should be_nil
      ensure
        File.delete(path) if File.exists?(path)
      end
    end

    it "keeps class-level @Validated when the endpoint has parameters" do
      source = <<-JAVA
        package com.example;
        import org.springframework.validation.annotation.Validated;
        import org.springframework.web.bind.annotation.GetMapping;
        import org.springframework.web.bind.annotation.RequestParam;
        import org.springframework.web.bind.annotation.RestController;

        @Validated
        @RestController
        public class ValidatedController {
          @GetMapping("/search")
          public String search(@RequestParam String q) {
            return q;
          }
        }
        JAVA

      path = File.join(Dir.tempdir, "ValidatedController-#{Process.pid}-#{Time.utc.to_unix_ms}.java")
      begin
        File.write(path, source)
        CodeLocator.instance.register_path(path)
        endpoint = build_endpoint(path, 10, "/search", "GET")
        endpoint.push_param(Param.new("q", "", "query"))

        SpringSecurityTagger.new(global_options).perform([endpoint])

        tag_named(endpoint, "input-validation").should_not be_nil
      ensure
        File.delete(path) if File.exists?(path)
      end
    end

    it "does not let the next Kotlin expression-bodied handler's @Valid leak into a parameterless handler" do
      source = <<-KOTLIN
        package com.example
        import jakarta.validation.Valid
        import org.springframework.web.bind.annotation.GetMapping
        import org.springframework.web.bind.annotation.PostMapping
        import org.springframework.web.bind.annotation.RequestBody
        import org.springframework.web.bind.annotation.RestController

        @RestController
        class ArticleController {
          @GetMapping("/articles")
          fun getAllArticles(): List<String> =
            listOf("one")

          @PostMapping("/articles")
          fun createArticle(@Valid @RequestBody article: Article): Article =
            article
        }
        KOTLIN

      path = File.join(Dir.tempdir, "ArticleController-#{Process.pid}-#{Time.utc.to_unix_ms}.kt")
      begin
        File.write(path, source)
        CodeLocator.instance.register_path(path)
        list_endpoint = build_endpoint(path, 10, "/articles", "GET")
        create_endpoint = build_endpoint(path, 14, "/articles", "POST")

        SpringSecurityTagger.new(global_options).perform([list_endpoint, create_endpoint])

        tag_named(list_endpoint, "input-validation").should be_nil
        tag_named(create_endpoint, "input-validation").should_not be_nil
      ensure
        File.delete(path) if File.exists?(path)
      end
    end
  end

  it "applies multiple independent tags to one handler" do
    load_fixture_files(global_base)
    endpoint = build_endpoint(controller, 12, "/api/posts", "POST")
    SpringSecurityTagger.new(global_options).perform([endpoint])

    tag_named(endpoint, "csrf-protection").should_not be_nil
    tag_named(endpoint, "cors").should_not be_nil
    tag_named(endpoint, "input-validation").should_not be_nil
  end

  it "handles empty code_paths gracefully (CSRF still resolves by URL)" do
    load_fixture_files(global_base)
    endpoint = build_endpoint(controller, nil, "/api/posts", "POST")
    SpringSecurityTagger.new(global_options).perform([endpoint])

    # No code_path → no annotation walk, but the config-level CSRF rule
    # still applies by URL/method without raising.
    tag_named(endpoint, "csrf-protection").should_not be_nil
    tag_named(endpoint, "cors").should be_nil
  end

  describe "csrf-protection via ignoringRequestMatchers" do
    it "flags only the paths CSRF is selectively ignored for" do
      load_fixture_files(extras_base)

      ignored = build_endpoint(webhook_ctrl, 10, "/api/webhook/github", "POST")
      SpringSecurityTagger.new(extras_options).perform([ignored])
      tag = tag_named(ignored, "csrf-protection")
      tag.should_not be_nil
      tag.not_nil!.description.should contain("ignoringRequestMatchers")

      # /admin/users is outside the ignored matcher and the chain is not
      # otherwise CSRF-disabled, so CSRF stays on → no tag.
      kept = build_endpoint(admin_ctrl, 10, "/admin/users", "POST")
      SpringSecurityTagger.new(extras_options).perform([kept])
      tag_named(kept, "csrf-protection").should be_nil
    end
  end

  describe "security-headers" do
    it "flags clickjacking protection disabled (frameOptions) for every endpoint in scope" do
      load_fixture_files(extras_base)
      endpoint = build_endpoint(admin_ctrl, 10, "/admin/users", "POST")
      SpringSecurityTagger.new(extras_options).perform([endpoint])

      tag = tag_named(endpoint, "security-headers")
      tag.should_not be_nil
      tag.not_nil!.tagger.should eq("spring_security")
      tag.not_nil!.description.should contain("Clickjacking")
    end

    it "applies to GET endpoints too (headers affect all responses)" do
      load_fixture_files(extras_base)
      endpoint = build_endpoint(webhook_ctrl, nil, "/api/webhook/list", "GET")
      SpringSecurityTagger.new(extras_options).perform([endpoint])

      tag_named(endpoint, "security-headers").should_not be_nil
    end

    it "is absent when the secure-default headers are left in place" do
      load_fixture_files(global_base)
      endpoint = build_endpoint(controller, 12, "/api/posts", "POST")
      SpringSecurityTagger.new(global_options).perform([endpoint])

      tag_named(endpoint, "security-headers").should be_nil
    end
  end

  describe "cors via global WebMvc config" do
    it "flags a permissive addMapping wildcard + credentials by URL" do
      load_fixture_files(extras_base)
      endpoint = build_endpoint(webhook_ctrl, nil, "/api/webhook/github", "POST")
      SpringSecurityTagger.new(extras_options).perform([endpoint])

      tag = tag_named(endpoint, "cors")
      tag.should_not be_nil
      tag.not_nil!.description.should contain("global WebMvc config")
      tag.not_nil!.description.should contain("credentials")
    end

    it "does not flag a URL outside the CORS mapping" do
      load_fixture_files(extras_base)
      endpoint = build_endpoint(admin_ctrl, nil, "/admin/users", "POST")
      SpringSecurityTagger.new(extras_options).perform([endpoint])

      tag_named(endpoint, "cors").should be_nil
    end
  end

  describe "cors via WebSocket/STOMP config" do
    it "flags a permissive addEndpoint wildcard by handshake URL" do
      source = <<-KOTLIN
        package com.example
        import org.springframework.context.annotation.Configuration
        import org.springframework.web.socket.config.annotation.StompEndpointRegistry
        import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer

        @Configuration
        class WebSocketConfig : WebSocketMessageBrokerConfigurer {
          override fun registerStompEndpoints(registry: StompEndpointRegistry) {
            registry.addEndpoint("/ws", "/portfolio")
              .setAllowedOrigins("*")
              .withSockJS()
          }
        }
        KOTLIN

      dir = File.join(Dir.tempdir, "spring-websocket-cors-#{Process.pid}-#{Time.utc.to_unix_ms}")
      path = File.join(dir, "WebSocketConfig.kt")
      begin
        Dir.mkdir_p(dir)
        File.write(path, source)
        CodeLocator.instance.register_path(path)

        options = create_test_options
        options["base"] = YAML::Any.new(dir)
        endpoint = build_endpoint(path, nil, "/portfolio", "GET")

        SpringSecurityTagger.new(options).perform([endpoint])

        tag = tag_named(endpoint, "cors")
        tag.should_not be_nil
        tag.not_nil!.description.should contain("WebSocket/STOMP endpoint config")
        tag.not_nil!.description.should contain("addEndpoint(\"/portfolio\")")
      ensure
        File.delete(path) if File.exists?(path)
        Dir.delete(dir) if Dir.exists?(dir)
      end
    end
  end
end

# Write `files` (path relative to a temp root => content), register them,
# and run SpringSecurityTagger over `routes` ("METHOD /path" => "relative
# controller path:line"). Returns each route's spring_security tag names.
private def spring_security_tags(files : Hash(String, String), routes : Hash(String, String)) : Hash(String, Array(String))
  CodeLocator.instance.clear_all
  root = File.tempname("spring_security_scope")
  files.each do |relative, source|
    path = File.join(root, relative)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, source)
    CodeLocator.instance.register_path(path)
  end
  options = create_test_options
  options["base"] = YAML::Any.new(root)
  endpoints = routes.map do |route, location|
    method, url = route.split(' ', 2)
    file, line = location.split(':')
    build_endpoint(File.join(root, file), line.to_i, url, method)
  end
  SpringSecurityTagger.new(options).perform(endpoints)
  FileUtils.rm_rf(root)
  routes.keys.zip(endpoints).to_h { |route, endpoint| {route, endpoint.tags.select(&.tagger.==("spring_security")).map(&.name)} }
end

describe "SpringSecurityTagger (scope of a rule)" do
  controller = "public class Controller {\n    public String a() { return \"\"; }\n}\n"
  admin_config = <<-JAVA
    @Configuration
    public class SecurityConfig implements WebMvcConfigurer {
        @Bean
        SecurityFilterChain chain(HttpSecurity http) throws Exception {
            http.csrf(c -> c.disable());
            return http.build();
        }

        @Override
        public void addCorsMappings(CorsRegistry registry) {
            registry.addMapping("/**").allowedOriginPatterns("*").allowCredentials(true);
        }
    }
    JAVA
  routes = {
    "POST /admin/users" => "admin-app/src/main/java/Controller.java:2",
    "POST /items"       => "public-app/src/main/java/Controller.java:2",
  }

  it "keeps CSRF and CORS settings of one Gradle build off a sibling build" do
    tags = spring_security_tags({
      "admin-app/build.gradle.kts"                  => "dependencies { implementation(\"org.springframework.boot:spring-boot-starter-security\") }\n",
      "admin-app/src/main/java/SecurityConfig.java" => admin_config,
      "admin-app/src/main/java/Controller.java"     => controller,
      "public-app/build.gradle.kts"                 => "dependencies { implementation(\"org.springframework.boot:spring-boot-starter-web\") }\n",
      "public-app/src/main/java/Controller.java"    => controller,
    }, routes)
    tags["POST /admin/users"].should eq(["csrf-protection", "cors"])
    tags["POST /items"].should be_empty
  end

  it "keeps CSRF and CORS settings of one Maven app off a sibling app" do
    tags = spring_security_tags({
      "admin-app/pom.xml"                           => "<project><artifactId>admin-app</artifactId><dependencies><dependency><artifactId>spring-boot-starter-security</artifactId></dependency></dependencies></project>",
      "admin-app/src/main/java/SecurityConfig.java" => admin_config,
      "admin-app/src/main/java/Controller.java"     => controller,
      "public-app/pom.xml"                          => "<project><artifactId>public-app</artifactId></project>",
      "public-app/src/main/java/Controller.java"    => controller,
    }, routes)
    tags["POST /admin/users"].should eq(["csrf-protection", "cors"])
    tags["POST /items"].should be_empty
  end

  it "applies them to a module that depends on the declaring one" do
    tags = spring_security_tags({
      "settings.gradle"                             => "include 'admin-app', 'public-app'\n",
      "admin-app/build.gradle"                      => "dependencies { implementation 'org.springframework.boot:spring-boot-starter-security' }\n",
      "admin-app/src/main/java/SecurityConfig.java" => admin_config,
      "public-app/build.gradle"                     => "dependencies { implementation project(':admin-app') }\n",
      "public-app/src/main/java/Controller.java"    => controller,
    }, {"POST /items" => "public-app/src/main/java/Controller.java:2"})
    tags["POST /items"].should eq(["csrf-protection", "cors"])
  end

  it "matches a CSRF or CORS path pattern as a whole path, not a prefix" do
    files = {
      "src/main/java/SecurityConfig.java" => <<-JAVA,
        public class SecurityConfig {
            @Bean
            SecurityFilterChain chain(HttpSecurity http) throws Exception {
                http.csrf(c -> c.ignoringRequestMatchers("/login", "/hooks/**"));
                return http.build();
            }
        }
        JAVA
      "src/main/java/StompConfig.java" => <<-JAVA,
        @Configuration
        @EnableWebSocketMessageBroker
        public class StompConfig implements WebSocketMessageBrokerConfigurer {
            @Override
            public void registerStompEndpoints(StompEndpointRegistry registry) {
                registry.addEndpoint("/").setAllowedOriginPatterns("*");
            }
        }
        JAVA
      "src/main/java/Controller.java" => controller,
    }
    tags = spring_security_tags(files, {
      "POST /login"                => "src/main/java/Controller.java:2",
      "POST /login-history/delete" => "src/main/java/Controller.java:2",
      "POST /hooks"                => "src/main/java/Controller.java:2",
      "POST /hooks/github"         => "src/main/java/Controller.java:2",
      "GET /"                      => "src/main/java/Controller.java:2",
      "GET /items"                 => "src/main/java/Controller.java:2",
    })
    tags["POST /login"].should eq(["csrf-protection"])
    tags["POST /login-history/delete"].should be_empty
    tags["POST /hooks"].should eq(["csrf-protection"])
    tags["POST /hooks/github"].should eq(["csrf-protection"])
    tags["GET /"].should eq(["cors"])
    tags["GET /items"].should be_empty
  end

  it "scopes a chain matched by servletPath(...).pattern(...) to the servlet path" do
    config = ->(servlet_path : String) do
      <<-JAVA
        public class WsSecurity {
            @Bean
            SecurityFilterChain wsChain(HttpSecurity http) throws Exception {
                http.securityMatcher(mvc.servletPath(#{servlet_path}).pattern("/**"))
                    .csrf(c -> c.disable());
                return http.build();
            }
        }
        JAVA
    end
    ws_routes = {"POST /items" => "src/main/java/Controller.java:2", "POST /ws/items" => "src/main/java/Controller.java:2"}
    tags = spring_security_tags({"src/main/java/WsSecurity.java" => config.call("\"/ws\""), "src/main/java/Controller.java" => controller}, ws_routes)
    tags["POST /items"].should be_empty
    tags["POST /ws/items"].should eq(["csrf-protection"])
    unread = spring_security_tags({"src/main/java/WsSecurity.java" => config.call("WS_PATH"), "src/main/java/Controller.java" => controller}, ws_routes)
    unread.values.flatten.should be_empty
  end

  it "reads a servlet path from a constant, a builder variable or across lines, as spring_auth does" do
    chain = ->(matcher : String) do
      <<-JAVA
        public class WsSecurity {
            static final String WS = "/ws";
            @Bean
            SecurityFilterChain wsChain(HttpSecurity http, HandlerMappingIntrospector introspector) throws Exception {
                MvcRequestMatcher.Builder mvc = new MvcRequestMatcher.Builder(introspector);
                MvcRequestMatcher.Builder ws = new MvcRequestMatcher.Builder(introspector).servletPath(WS);
                http.securityMatcher(#{matcher})
                    .csrf(c -> c.disable());
                return http.build();
            }
        }
        JAVA
    end
    ws_routes = {"POST /items" => "src/main/java/Controller.java:2", "POST /ws/items" => "src/main/java/Controller.java:2"}
    ["mvc.servletPath(WS).pattern(\"/**\")", "ws.pattern(\"/**\")", "mvc.servletPath(\"/ws\")\n                .pattern(\"/**\")"].each do |matcher|
      tags = spring_security_tags({"src/main/java/WsSecurity.java" => chain.call(matcher), "src/main/java/Controller.java" => controller}, ws_routes)
      tags["POST /items"].should be_empty
      tags["POST /ws/items"].should eq(["csrf-protection"])
    end
  end

  it "matches a RegexRequestMatcher CSRF exemption as a regex" do
    config = <<-JAVA
      public class SecurityConfig {
          @Bean
          SecurityFilterChain chain(HttpSecurity http) throws Exception {
              http.csrf(c -> c.ignoringRequestMatchers(new RegexRequestMatcher("/rx/.*", null)));
              return http.build();
          }
      }
      JAVA
    tags = spring_security_tags({"src/main/java/SecurityConfig.java" => config, "src/main/java/Controller.java" => controller}, {
      "POST /rx/q"  => "src/main/java/Controller.java:2",
      "POST /other" => "src/main/java/Controller.java:2",
    })
    tags["POST /rx/q"].should eq(["csrf-protection"])
    tags["POST /other"].should be_empty
  end
end
