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
    locator.push("file_map", file)
  end
end

private def build_endpoint(path : String, line : Int32?, url : String, method : String) : Endpoint
  details = line ? Details.new(PathInfo.new(path, line)) : Details.new
  details.technology = "java_spring"
  Endpoint.new(url, method, [] of Param, details)
end

describe "SpringSecurityTagger" do
  global_base = "#{__DIR__}/../../../functional_test/fixtures/java/spring_security"
  controller = "#{global_base}/src/main/java/com/example/ApiController.java"

  scoped_base = "#{__DIR__}/../../../functional_test/fixtures/java/spring_security_scoped"

  global_options = create_test_options
  global_options["base"] = YAML::Any.new(global_base)

  scoped_options = create_test_options
  scoped_options["base"] = YAML::Any.new(scoped_base)

  extras_base = "#{__DIR__}/../../../functional_test/fixtures/java/spring_security_extras"
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
        CodeLocator.instance.push("file_map", path)
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
        CodeLocator.instance.push("file_map", path)
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
        CodeLocator.instance.push("file_map", path)
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
        CodeLocator.instance.push("file_map", path)

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
