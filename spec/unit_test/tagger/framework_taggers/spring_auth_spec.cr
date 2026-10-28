require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Write `source` to a temp controller file and run SpringAuthTagger against a
# single endpoint whose handler is recorded at `line`.
def run_spring_class_level(source : String, line : Int32, ext : String = "java") : Endpoint
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("spring_class_level")
  Dir.mkdir_p(tmpdir)
  file = File.join(tmpdir, "AdminController.#{ext}")
  File.write(file, source)
  CodeLocator.instance.register_path(file)

  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(tmpdir)
  details = Details.new(PathInfo.new(file, line))
  details.technology = "java_spring"
  endpoint = Endpoint.new("/admin/users", "GET", [] of Param, details)

  SpringAuthTagger.new(noir_options).perform([endpoint])
  FileUtils.rm_rf(tmpdir)
  endpoint
end

# Write each `name => source` under a temp `src/main/java/com/example/`,
# run SpringAuthTagger over `routes` ("METHOD /path") and return each
# route's auth tag descriptions.
def run_spring_security_config(files : Hash(String, String), routes : Array(String)) : Hash(String, Array(String))
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("spring_security_config")
  dir = File.join(tmpdir, "src/main/java/com/example")
  Dir.mkdir_p(dir)
  files.each do |name, source|
    path = File.join(dir, name)
    File.write(path, source)
    CodeLocator.instance.register_path(path)
  end
  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(tmpdir)
  endpoints = routes.map { |route| Endpoint.new(route.split(' ', 2)[1], route.split(' ', 2)[0]) }
  SpringAuthTagger.new(noir_options).perform(endpoints)
  FileUtils.rm_rf(tmpdir)
  routes.zip(endpoints).to_h { |route, endpoint| {route, endpoint.tags.select(&.name.==("auth")).map(&.description)} }
end

describe "SpringAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/java/spring_auth", __DIR__)
  controller_path = "#{fixture_base}/src/main/java/com/example/Controller.java"
  open_controller_path = "#{fixture_base}/src/main/java/com/example/OpenController.java"

  # Controller.java line reference:
  # 12: @PreAuthorize("hasRole('ADMIN')")
  # 13: @GetMapping("/admin/users")
  # 14: public String getUsers() {
  # 18: @Secured("ROLE_USER")
  # 19: @PostMapping("/posts")
  # 20: public String createPost() {
  # 24: @RolesAllowed({"ROLE_ADMIN", "ROLE_MANAGER"})
  # 25: @DeleteMapping("/posts/{id}")
  # 26: public String deletePost(@PathVariable Long id) {

  before_each do
    CodeLocator.instance.clear_all
  end

  # Regression: in production, options["base"] is always wrapped in an
  # Array(YAML::Any) by the CLI. The previous `@base_path =
  # options["base"].to_s` stringified the array as `["…"]`, so every
  # `get_files_by_prefix_and_extension(@base_path, …)` call returned
  # nothing and the tagger silently no-op'd. The spec below mirrors
  # the CLI shape (array of base paths) instead of the bare string
  # form that masked the bug.
  it "still detects @PreAuthorize when options[\"base\"] is wrapped in an array (CLI shape)" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new([YAML::Any.new(fixture_base)])

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(controller_path, 14))
    details.technology = "java_spring"
    endpoint = Endpoint.new("/api/admin/users", "GET", [] of Param, details)

    tagger = SpringAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("spring_auth")
  end

  it "detects @PreAuthorize annotation" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(controller_path, 14))
    details.technology = "java_spring"
    endpoint = Endpoint.new("/api/admin/users", "GET", [] of Param, details)

    tagger = SpringAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("spring_auth")
    endpoint.tags[0].description.should contain("@PreAuthorize")
  end

  it "detects @Secured annotation" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(controller_path, 20))
    details.technology = "java_spring"
    endpoint = Endpoint.new("/api/posts", "POST", [] of Param, details)

    tagger = SpringAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("@Secured")
  end

  it "detects @RolesAllowed annotation" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(controller_path, 26))
    details.technology = "java_spring"
    endpoint = Endpoint.new("/api/posts/1", "DELETE", [] of Param, details)

    tagger = SpringAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("@RolesAllowed")
  end

  it "does not tag open controller endpoints (no annotations)" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(open_controller_path, 9))
    details.technology = "java_spring"
    endpoint = Endpoint.new("/api/public/health", "GET", [] of Param, details)

    tagger = SpringAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "uses unscoped anyRequest authenticated as a fallback auth rule" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    endpoint = Endpoint.new("/api/other", "GET")

    tagger = SpringAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.any? { |tag| tag.name == "auth" && tag.description.includes?("anyRequest") }.should be_true
  end

  it "reads every rule of a one-line lambda DSL chain" do
    tmpdir = File.tempname("spring_one_line_dsl")
    Dir.mkdir_p(tmpdir)
    config = File.join(tmpdir, "SecurityConfig.java")
    File.write(config, <<-JAVA)
      public class SecurityConfig {
          @Bean
          public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(auth -> auth.requestMatchers("/public/**").permitAll().anyRequest().authenticated());
              return http.build();
          }
      }
      JAVA
    CodeLocator.instance.register_path(config)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    items = Endpoint.new("/items", "GET")
    info = Endpoint.new("/public/info", "GET")
    SpringAuthTagger.new(noir_options).perform([items, info])
    FileUtils.rm_rf(tmpdir)

    items.tags.map(&.description).should eq(["Protected by Spring Security authenticated via anyRequest()"])
    info.tags.empty?.should be_true
  end

  it "keeps anyRequest fallback for an unscoped chain when another chain is scoped" do
    temp_dir = File.join(Dir.tempdir, "noir-spring-auth-mixed-chain-#{Process.pid}-#{Time.utc.to_unix_ms}")
    config_path = File.join(temp_dir, "src/main/java/com/example/SecurityConfiguration.java")

    begin
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, <<-JAVA)
        package com.example;

        import org.springframework.context.annotation.Bean;
        import org.springframework.security.config.annotation.web.builders.HttpSecurity;
        import org.springframework.security.web.SecurityFilterChain;

        class SecurityConfiguration {
            @Bean
            SecurityFilterChain apiChain(HttpSecurity http) throws Exception {
                return http.securityMatcher("/api/**")
                    .authorizeHttpRequests(auth -> auth.anyRequest().authenticated())
                    .build();
            }

            @Bean
            SecurityFilterChain defaultChain(HttpSecurity http) throws Exception {
                return http.authorizeHttpRequests(auth -> auth.anyRequest().authenticated()).build();
            }
        }
        JAVA

      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(temp_dir)
      CodeLocator.instance.register_path(config_path)

      endpoint = Endpoint.new("/web/dashboard", "GET")

      tagger = SpringAuthTagger.new(noir_options)
      tagger.perform([endpoint])

      endpoint.tags.any? { |tag| tag.name == "auth" && tag.description.includes?("anyRequest") }.should be_true
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  end

  it "treats a chain using plural antMatchers rules as unscoped (Spring 5 form)" do
    # Regression: plural `antMatchers(...)` are authorization *rules*, not a
    # chain scope restriction. A substring test like `includes?("antMatcher")`
    # wrongly flagged this chain as scoped and dropped its `anyRequest()`
    # fallback, so endpoints not matching an explicit rule lost their auth tag.
    temp_dir = File.join(Dir.tempdir, "noir-spring-auth-antmatchers-#{Process.pid}-#{Time.utc.to_unix_ms}")
    config_path = File.join(temp_dir, "src/main/java/com/example/SecurityConfiguration.java")

    begin
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, <<-JAVA)
        package com.example;

        import org.springframework.context.annotation.Bean;
        import org.springframework.security.config.annotation.web.builders.HttpSecurity;
        import org.springframework.security.web.SecurityFilterChain;

        class SecurityConfiguration {
            @Bean
            SecurityFilterChain chain(HttpSecurity http) throws Exception {
                return http.authorizeRequests()
                    .antMatchers("/public/**").permitAll()
                    .anyRequest().authenticated()
                    .build();
            }
        }
        JAVA

      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(temp_dir)
      CodeLocator.instance.register_path(config_path)

      public_endpoint = Endpoint.new("/public/health", "GET")
      protected_endpoint = Endpoint.new("/secure/data", "GET")

      tagger = SpringAuthTagger.new(noir_options)
      tagger.perform([public_endpoint, protected_endpoint])

      public_endpoint.tags.empty?.should be_true
      protected_endpoint.tags.any? { |tag| tag.name == "auth" && tag.description.includes?("anyRequest") }.should be_true
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  end

  it "preserves HttpMethod-specific permitAll matchers before applying anyRequest fallback" do
    temp_dir = File.join(Dir.tempdir, "noir-spring-auth-method-rule-#{Process.pid}-#{Time.utc.to_unix_ms}")
    config_path = File.join(temp_dir, "src/main/java/com/example/SecurityConfiguration.java")

    begin
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, <<-JAVA)
        package com.example;

        import org.springframework.context.annotation.Bean;
        import org.springframework.http.HttpMethod;
        import org.springframework.security.config.annotation.web.builders.HttpSecurity;
        import org.springframework.security.web.SecurityFilterChain;

        class SecurityConfiguration {
            @Bean
            SecurityFilterChain chain(HttpSecurity http) throws Exception {
                return http.authorizeHttpRequests(auth -> auth
                    .requestMatchers(HttpMethod.GET, "/public/**").permitAll()
                    .anyRequest().authenticated()
                ).build();
            }
        }
        JAVA

      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(temp_dir)
      CodeLocator.instance.register_path(config_path)

      public_get = Endpoint.new("/public/status", "GET")
      protected_post = Endpoint.new("/public/status", "POST")

      tagger = SpringAuthTagger.new(noir_options)
      tagger.perform([public_get, protected_post])

      public_get.tags.empty?.should be_true
      protected_post.tags.any? { |tag| tag.name == "auth" && tag.description.includes?("anyRequest") }.should be_true
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  end

  it "names the methods a method-scoped matcher exempts from an any-method route's decision" do
    config = <<-JAVA
      package com.example;

      import org.springframework.http.HttpMethod;

      class SecurityConfig {
          SecurityFilterChain chain(HttpSecurity http) throws Exception {
              return http.authorizeHttpRequests(auth -> auth
                  .requestMatchers(HttpMethod.GET, "/", "/*.html").permitAll()
                  .requestMatchers(HttpMethod.DELETE, "/open/**").authenticated()
                  .anyRequest().permitAll()
              ).build();
          }
      }
      JAVA
    tags = run_spring_security_config({"SecurityConfig.java" => config}, ["ANY /", "ANY /open/x", "ANY /other"])
    tags["ANY /"].should be_empty
    tags["ANY /open/x"].should eq(["Protected by Spring Security authenticated via requestMatchers(\"/open/**\"), for DELETE only"])
    tags["ANY /other"].should be_empty

    guarded = config.sub(".anyRequest().permitAll()", ".anyRequest().authenticated()")
    tags = run_spring_security_config({"SecurityConfig.java" => guarded}, ["ANY /", "GET /", "POST /"])
    tags["ANY /"].should eq(["Protected by Spring Security authenticated via anyRequest(), except for GET, which is not guarded (Public by Spring Security permitAll via requestMatchers(\"/\"))"])
    tags["GET /"].should be_empty
    tags["POST /"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
  end

  it "leaves the routes a Spring Security filter answers unguarded" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("spring_security_filter")
    path = File.join(tmpdir, "src/main/java/com/example/SecurityConfig.java")
    Dir.mkdir_p(File.dirname(path))
    File.write(path, "class SecurityConfig { SecurityFilterChain c(HttpSecurity http) { return http.authorizeHttpRequests(a -> a.anyRequest().authenticated()).logout(l -> l.logoutUrl(\"/logout\")).build(); } }")
    CodeLocator.instance.register_path(path)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    logout = Endpoint.new("/logout", "POST")
    logout.add_tag(Analyzer::Java::JavaEngine::SECURITY_FILTER_TAG)
    actuator = Endpoint.new("/actuator/health", "GET")
    actuator.add_tag(Analyzer::Java::JavaEngine::FRAMEWORK_PROVIDED_TAG)
    SpringAuthTagger.new(noir_options).perform([logout, actuator])
    FileUtils.rm_rf(tmpdir)
    logout.tags.none?(&.name.==("auth")).should be_true
    actuator.tags.any?(&.name.==("auth")).should be_true
  end

  it "reads the Kotlin authorizeHttpRequests DSL" do
    temp_dir = File.join(Dir.tempdir, "noir-spring-auth-kotlin-dsl-#{Process.pid}-#{Time.utc.to_unix_ms}")
    config_path = File.join(temp_dir, "src/main/kotlin/com/example/SecurityConfig.kt")

    begin
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, <<-KT)
        package com.example

        import org.springframework.security.config.annotation.web.builders.HttpSecurity
        import org.springframework.security.config.annotation.web.invoke
        import org.springframework.security.web.SecurityFilterChain

        class SecurityConfig {
            fun filterChain(http: HttpSecurity): SecurityFilterChain {
                http {
                    authorizeHttpRequests {
                        authorize("/public/**", permitAll)
                        authorize(HttpMethod.POST, "/admin/**", hasRole("ADMIN"))
                        authorize(anyRequest, authenticated)
                    }
                }
                return http.build()
            }
        }
        KT

      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(temp_dir)
      CodeLocator.instance.register_path(config_path)

      open = Endpoint.new("/public/hello", "GET")
      admin = Endpoint.new("/admin/users", "POST")
      me = Endpoint.new("/me", "GET")

      SpringAuthTagger.new(noir_options).perform([open, admin, me])

      open.tags.should be_empty
      admin.tags.map(&.description).should eq(["Protected by Spring Security hasRole via authorize(\"/admin/**\")"])
      me.tags.map(&.description).should eq(["Protected by Spring Security authenticated via authorize(anyRequest)"])
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  end

  it "lets a more-specific permitAll matcher suppress a broader protected matcher" do
    temp_dir = File.join(Dir.tempdir, "noir-spring-auth-permit-#{Process.pid}-#{Time.utc.to_unix_ms}")
    config_path = File.join(temp_dir, "src/main/kotlin/com/example/SecurityConfiguration.kt")

    begin
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, <<-KT)
        package com.example

        import org.springframework.security.config.annotation.web.builders.HttpSecurity
        import org.springframework.security.web.SecurityFilterChain

        class SecurityConfiguration {
            fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
                return http.authorizeHttpRequests { request ->
                    request.requestMatchers("/user/register").permitAll()
                        .requestMatchers("/user/**").hasRole("SUPERADM")
                }.build()
            }
        }
        KT

      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(temp_dir)
      CodeLocator.instance.register_path(config_path)

      public_endpoint = Endpoint.new("/user/register", "POST")
      protected_endpoint = Endpoint.new("/user/profile", "GET")

      tagger = SpringAuthTagger.new(noir_options)
      tagger.perform([public_endpoint, protected_endpoint])

      public_endpoint.tags.empty?.should be_true
      protected_endpoint.tags.any? { |tag| tag.name == "auth" && tag.description.includes?("hasRole") }.should be_true
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  end

  it "matches Kotlin requestMatchers without a leading slash and access blocks" do
    temp_dir = File.join(Dir.tempdir, "noir-spring-auth-access-#{Process.pid}-#{Time.utc.to_unix_ms}")
    config_path = File.join(temp_dir, "src/main/kotlin/com/example/SecurityConfiguration.kt")

    begin
      Dir.mkdir_p(File.dirname(config_path))
      File.write(config_path, <<-KT)
        package com.example

        import org.springframework.security.config.annotation.web.builders.HttpSecurity
        import org.springframework.security.web.SecurityFilterChain

        class SecurityConfiguration {
            fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
                return http.authorizeHttpRequests { request ->
                    request.requestMatchers("api/v1/teams/*").access { authentication, _ -> true }
                }.build()
            }
        }
        KT

      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(temp_dir)
      CodeLocator.instance.register_path(config_path)

      endpoint = Endpoint.new("/api/v1/teams/{nation}", "GET")

      tagger = SpringAuthTagger.new(noir_options)
      tagger.perform([endpoint])

      endpoint.tags.any? { |tag| tag.name == "auth" && tag.description.includes?("access") }.should be_true
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "java_spring"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = SpringAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end

# A controller-level `@PreAuthorize`/`@Secured`/`@RolesAllowed` guards every
# handler the class declares. The per-handler backward walk stops at the
# `public`/`class` boundary by design, so it can never reach the class
# declaration — every handler of an `@PreAuthorize("hasRole('ADMIN')")`
# controller was reported as unauthenticated.
describe "SpringAuthTagger (class-level annotations)" do
  before_each do
    CodeLocator.instance.clear_all
  end

  #  1 package com.example;
  #  2 (blank)
  #  3 @RestController
  #  4 @RequestMapping("/admin")
  #  5 @PreAuthorize("hasRole('ADMIN')")
  #  6 public class AdminController {
  #  7 (blank)
  #  8     @GetMapping("/users")
  #  9     public String listUsers() {
  # 10         return "users";
  # 11     }
  # 12 }
  guarded = <<-JAVA
    package com.example;

    @RestController
    @RequestMapping("/admin")
    @PreAuthorize("hasRole('ADMIN')")
    public class AdminController {

        @GetMapping("/users")
        public String listUsers() {
            return "users";
        }
    }
    JAVA

  it "detects a class-level @PreAuthorize" do
    endpoint = run_spring_class_level(guarded, 9)
    endpoint.tags.any? { |t| t.name == "auth" && t.description.includes?("@PreAuthorize") }.should be_true
  end

  it "detects a class-level @Secured" do
    endpoint = run_spring_class_level(guarded.gsub("@PreAuthorize(\"hasRole('ADMIN')\")", "@Secured(\"ROLE_ADMIN\")"), 9)
    endpoint.tags.any? { |t| t.name == "auth" && t.description.includes?("@Secured") }.should be_true
  end

  it "detects a class-level @RolesAllowed" do
    endpoint = run_spring_class_level(guarded.gsub("@PreAuthorize(\"hasRole('ADMIN')\")", "@RolesAllowed({\"ROLE_ADMIN\"})"), 9)
    endpoint.tags.any? { |t| t.name == "auth" && t.description.includes?("@RolesAllowed") }.should be_true
  end

  it "detects a class-level annotation on a Kotlin controller" do
    kotlin = <<-KT
      package com.example

      @RestController
      @PreAuthorize("hasRole('ADMIN')")
      class AdminController(private val service: Service) {

          @GetMapping("/users")
          fun listUsers(): String = "users"
      }
      KT
    endpoint = run_spring_class_level(kotlin, 8, "kt")
    endpoint.tags.any? { |t| t.name == "auth" }.should be_true
  end

  it "does not tag a controller without a class-level annotation" do
    # Same shape, annotation removed — proves the class-level check is not a
    # blanket "any @PreAuthorize anywhere in the file" match.
    open = <<-JAVA
      package com.example;

      @RestController
      @RequestMapping("/admin")
      public class AdminController {

          @GetMapping("/users")
          public String listUsers() {
              return "users";
          }
      }
      JAVA
    endpoint = run_spring_class_level(open, 8)
    endpoint.tags.any? { |t| t.name == "auth" }.should be_false
  end

  it "does not treat a method-level annotation as class-level" do
    # `@PreAuthorize` guards only `secret()`; `listUsers()` above it is open.
    mixed = <<-JAVA
      package com.example;

      @RestController
      public class AdminController {

          @GetMapping("/users")
          public String listUsers() {
              return "users";
          }

          @PreAuthorize("hasRole('ADMIN')")
          @GetMapping("/secret")
          public String secret() {
              return "secret";
          }
      }
      JAVA
    endpoint = run_spring_class_level(mixed, 7)
    endpoint.tags.any? { |t| t.name == "auth" }.should be_false
  end

  it "stops the annotation walk at the previous handler's bodiless declaration" do
    kotlin = <<-KT
      @RestController
      class AdminController {
          @PreAuthorize("hasRole('ADMIN')")
          @GetMapping("/admin")
          fun admin() = "admin"

          @GetMapping("/health")
          fun health() = "ok"
      }
      KT
    run_spring_class_level(kotlin, 7, "kt").tags.any? { |t| t.name == "auth" }.should be_false
    run_spring_class_level(kotlin, 4, "kt").tags.any? { |t| t.name == "auth" }.should be_true

    java_interface = <<-JAVA
      public interface AdminApi {
          @PreAuthorize("hasRole('ADMIN')")
          @GetMapping("/admin")
          String admin();
          @GetMapping("/health")
          String health();
      }
      JAVA
    run_spring_class_level(java_interface, 5).tags.any? { |t| t.name == "auth" }.should be_false
    run_spring_class_level(java_interface, 3).tags.any? { |t| t.name == "auth" }.should be_true
  end

  it "resolves String and String[] constants, multi-line matcher lists and matcher factories" do
    config = <<-JAVA
      package com.example;

      import static com.example.Paths.HOOKS;

      public class SecurityConfig {
          public static final String API = "/api/**";
          private static final String[] OPEN = new String[]{"/api/noauth/**", Paths.BASE + "/public/**"};
          static final String[] DOCS = {"/api/docs"};

          @Bean
          SecurityFilterChain chain(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(config -> config
                      .requestMatchers(OPEN).permitAll() // anonymous (no token)
                      .requestMatchers(
                              DOCS, // docs (public)
                              Paths.LOGIN).permitAll()
                      .requestMatchers(antMatcher(HOOKS)).permitAll()
                      .requestMatchers(API).authenticated()
                      .anyRequest().permitAll());
              return http.build();
          }
      }
      JAVA
    paths = <<-JAVA
      package com.example;

      public final class Paths {
          public static final String BASE = "/api/v2";
          public static final String LOGIN = "/api/auth/login";
          public static final String HOOKS = "/api/hooks/**";
      }
      JAVA
    tags = run_spring_security_config({"SecurityConfig.java" => config, "Paths.java" => paths},
      ["GET /api/noauth/reset", "GET /api/v2/public/r/1", "GET /api/docs", "POST /api/auth/login", "POST /api/hooks/x", "GET /api/users", "GET /index.html"])
    tags["GET /api/noauth/reset"].should be_empty
    tags["GET /api/v2/public/r/1"].should be_empty
    tags["GET /api/docs"].should be_empty
    tags["POST /api/auth/login"].should be_empty
    tags["POST /api/hooks/x"].should be_empty
    tags["GET /api/users"].should eq(["Protected by Spring Security authenticated via requestMatchers(\"/api/**\")"])
    tags["GET /index.html"].should be_empty
  end

  it "decides a request inside a securityMatcher-scoped chain by that chain alone" do
    config = <<-JAVA
      package com.example;

      public class SecurityConfig {
          public static final String DEVICE_API = "/api/v1/**";

          @Bean
          @Order(1)
          SecurityFilterChain devices(HttpSecurity http) throws Exception {
              http.securityMatcher(AntPathRequestMatcher.antMatcher(DEVICE_API))
                  .authorizeHttpRequests(config -> config.requestMatchers(DEVICE_API).permitAll());
              return http.build();
          }

          @Bean
          @Order(2)
          SecurityFilterChain admin(HttpSecurity http) throws Exception {
              http.securityMatchers(matchers -> matchers.requestMatchers("/admin/**"))
                  .authorizeHttpRequests(config -> config.anyRequest().hasRole("ADMIN"));
              return http.build();
          }

          @Bean
          SecurityFilterChain main(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(config -> config
                      .requestMatchers("/api/**").authenticated()
                      .requestMatchers(antMatcher("/h2/**")).permitAll()
                      .anyRequest().authenticated());
              return http.build();
          }
      }
      JAVA
    tags = run_spring_security_config({"SecurityConfig.java" => config},
      ["POST /api/v1/{token}/telemetry", "GET /admin/users", "GET /api/users", "GET /h2/console", "GET /other"])
    tags["POST /api/v1/{token}/telemetry"].should be_empty
    tags["GET /admin/users"].should eq(["Protected by Spring Security hasRole via anyRequest()"])
    tags["GET /api/users"].should eq(["Protected by Spring Security authenticated via requestMatchers(\"/api/**\")"])
    tags["GET /h2/console"].should be_empty
    tags["GET /other"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
  end

  it "orders overlapping scoped chains by @Order and matches a bare prefix against /**" do
    config = <<-JAVA
      public class SecurityConfig {
          @Bean
          @Order(5)
          SecurityFilterChain api(HttpSecurity http) throws Exception {
              http.securityMatcher("/api/**").authorizeHttpRequests(c -> c.anyRequest().authenticated());
              return http.build();
          }

          @Bean
          @Order(Ordered.HIGHEST_PRECEDENCE)
          SecurityFilterChain open(HttpSecurity http) throws Exception {
              http.securityMatcher("/api/open/**").authorizeHttpRequests(c -> c.anyRequest().permitAll());
              return http.build();
          }
      }
      JAVA
    tags = run_spring_security_config({"SecurityConfig.java" => config}, ["GET /api/open/x", "GET /api/open", "GET /api", "GET /api/x"])
    tags["GET /api/open/x"].should be_empty
    tags["GET /api/open"].should be_empty
    tags["GET /api"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
    tags["GET /api/x"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
  end
end

# Write `files` (path relative to a temp root => content), register them,
# and run SpringAuthTagger over `routes` ("METHOD /path" => "relative
# controller path:line"). Returns each route's auth tag descriptions.
def run_spring_multi_module(files : Hash(String, String), routes : Hash(String, String)) : Hash(String, Array(String))
  CodeLocator.instance.clear_all
  root = File.tempname("spring_multi_module")
  files.each do |relative, source|
    path = File.join(root, relative)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, source)
    CodeLocator.instance.register_path(path)
  end
  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(root)
  endpoints = routes.map do |route, location|
    method, url = route.split(' ', 2)
    file, line = location.split(':')
    Endpoint.new(url, method, [] of Param, Details.new(PathInfo.new(File.join(root, file), line.to_i)))
  end
  SpringAuthTagger.new(noir_options).perform(endpoints)
  FileUtils.rm_rf(root)
  routes.keys.zip(endpoints).to_h { |route, endpoint| {route, endpoint.tags.select(&.name.==("auth")).map(&.description)} }
end

def spring_module_pom(artifact : String, deps : Array(String)) : String
  "<project><parent><artifactId>root</artifactId></parent><artifactId>#{artifact}</artifactId><dependencies>" +
    deps.map { |dep| "<dependency><artifactId>#{dep}</artifactId></dependency>" }.join + "</dependencies></project>"
end

describe "SpringAuthTagger (multi-module projects)" do
  security_config = <<-JAVA
    package com.example.security;

    import com.example.security.props.IgnoreUrlsConfig;

    public class SecurityConfig {
        @Autowired
        private IgnoreUrlsConfig ignoreUrlsConfig;

        @Bean
        SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
            http.authorizeHttpRequests(registry -> {
                for (String url : ignoreUrlsConfig.getUrls()) {
                    registry.requestMatchers(url).permitAll();
                }
            }).authorizeHttpRequests(registry -> registry.anyRequest().authenticated());
            return http.build();
        }
    }
    JAVA
  ignore_urls = <<-JAVA
    package com.example.security.props;

    @ConfigurationProperties(prefix = "secure.ignored")
    public class IgnoreUrlsConfig {
        private List<String> urls = new ArrayList<>();
    }
    JAVA
  controller = <<-JAVA
    public class Controller {
        @GetMapping("/x")
        public String x() { return "x"; }
    }
    JAVA
  files = {
    "pom.xml"                                                                 => "<project><artifactId>root</artifactId><dependencyManagement><dependencies><dependency><artifactId>security</artifactId></dependency></dependencies></dependencyManagement></project>",
    "security/pom.xml"                                                        => spring_module_pom("security", ["spring-boot-starter-security"]),
    "security/src/main/java/com/example/security/SecurityConfig.java"         => security_config,
    "security/src/main/java/com/example/security/props/IgnoreUrlsConfig.java" => ignore_urls,
    "admin/pom.xml"                                                           => spring_module_pom("admin", ["security"]),
    "admin/src/main/resources/application.yml"                                => "spring:\n  profiles:\n    active: dev\nsecure:\n  ignored:\n    urls:\n      - /admin/login\n      - /*/*.html\n",
    "admin/src/main/java/com/example/admin/Controller.java"                   => controller,
    "portal/pom.xml"                                                          => spring_module_pom("portal", ["security"]),
    "portal/src/main/resources/application.properties"                        => "secure.ignored.urls[0]=/product/**\n",
    "portal/src/main/java/com/example/portal/Controller.java"                 => controller,
    "search/pom.xml"                                                          => spring_module_pom("search", ["spring-boot-starter-web"]),
    "search/src/main/java/com/example/search/Controller.java"                 => controller,
    "other/pom.xml"                                                           => spring_module_pom("other", ["spring-boot-starter-security"]),
    "other/src/main/java/com/example/other/Controller.java"                   => controller,
    "staged/pom.xml"                                                          => spring_module_pom("staged", ["security"]),
    "staged/src/main/resources/application.yml"                               => "secure:\n  ignored:\n    urls: /open/**\n",
    "staged/src/main/resources/application-dev.yml"                           => "secure:\n  ignored:\n    urls: /dev/**\n",
    "staged/src/main/java/com/example/staged/Controller.java"                 => controller,
    "lib/pom.xml"                                                             => spring_module_pom("lib", [] of String),
    "lib/src/main/java/com/example/lib/Controller.java"                       => controller,
    "app/pom.xml"                                                             => spring_module_pom("app", ["lib", "security"]),
  }

  it "reads a @ConfigurationProperties permitAll list from the serving module's own configuration" do
    tags = run_spring_multi_module(files, {
      "POST /admin/login"       => "admin/src/main/java/com/example/admin/Controller.java:2",
      "GET /admin/users"        => "admin/src/main/java/com/example/admin/Controller.java:2",
      "GET /product/updateInfo" => "admin/src/main/java/com/example/admin/Controller.java:2",
      "GET /product/detail/1"   => "portal/src/main/java/com/example/portal/Controller.java:2",
      "POST /admin/login2"      => "portal/src/main/java/com/example/portal/Controller.java:2",
    })
    tags["POST /admin/login"].should be_empty
    tags["GET /admin/users"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
    # `/product/**` is whitelisted by the portal's configuration, not the admin's.
    tags["GET /product/updateInfo"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
    tags["GET /product/detail/1"].should be_empty
    tags["POST /admin/login2"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
  end

  it "keeps the guard, with a note, when a profile sets the list too" do
    tags = run_spring_multi_module(files, {"GET /open/x" => "staged/src/main/java/com/example/staged/Controller.java:2"})
    tags["GET /open/x"].size.should eq(1)
    tags["GET /open/x"][0].should start_with("Protected by Spring Security authenticated via anyRequest(); a setting can exempt paths")
    tags["GET /open/x"][0].should contain("application-dev.yml")
  end

  it "applies a chain only to modules that depend on the module declaring it" do
    tags = run_spring_multi_module(files, {
      "GET /search" => "search/src/main/java/com/example/search/Controller.java:2",
      "GET /other"  => "other/src/main/java/com/example/other/Controller.java:2",
      "GET /lib"    => "lib/src/main/java/com/example/lib/Controller.java:2",
    })
    tags["GET /search"].should be_empty
    # A library's controller runs behind the chains of the app that includes it.
    tags["GET /lib"].should eq(["Protected by Spring Security authenticated via anyRequest(); a setting can exempt paths from it: the permitAll list bound from secure.ignored.urls"])
    # Spring Security on the classpath without any of the project's chains: Boot's default.
    tags["GET /other"].size.should eq(1)
    tags["GET /other"][0].should start_with("Protected by Spring Boot default security")
  end

  it "reads the list from the app that runs a library's controller, not the library's own file" do
    tags = run_spring_multi_module(files.merge({
      "lib/src/main/resources/application.yml" => "secure:\n  ignored:\n    urls:\n      - /lib/**\n",
      "app/src/main/resources/application.yml" => "secure:\n  ignored:\n    urls:\n      - /public/**\n",
    }), {"GET /lib/x" => "lib/src/main/java/com/example/lib/Controller.java:2"})
    tags["GET /lib/x"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
  end

  it "judges a library file by the Boot app that serves it, not as an app of its own" do
    tags = run_spring_multi_module(files.merge({
      "slib/pom.xml"                                        => spring_module_pom("slib", ["spring-boot-starter-security"]),
      "slib/src/main/resources/static/x.js"                 => "1;\n",
      "sapp/pom.xml"                                        => spring_module_pom("sapp", ["slib", "security"]),
      "sapp/src/main/java/com/example/sapp/App.java"        => "@SpringBootApplication\npublic class App {}\n",
      "sapp/src/main/resources/application.yml"             => "secure:\n  ignored:\n    urls:\n      - /static/**\n",
      "other/src/main/java/com/example/other/OtherApp.java" => "@SpringBootApplication\npublic class OtherApp {}\n",
    }), {
      "GET /static/x.js" => "slib/src/main/resources/static/x.js:1",
      "GET /other"       => "other/src/main/java/com/example/other/Controller.java:2",
    })
    tags["GET /static/x.js"].should be_empty
    tags["GET /other"][0].should start_with("Protected by Spring Boot default security")
  end

  it "keeps the guard when configuration is imported or set beside the module" do
    imported = files.merge({"admin/src/main/resources/application.yml" => "spring:\n  config:\n    import: optional:configserver:http://config:8888\nsecure:\n  ignored:\n    urls:\n      - /admin/login\n"})
    tags = run_spring_multi_module(imported, {"POST /admin/login" => "admin/src/main/java/com/example/admin/Controller.java:2"})
    tags["POST /admin/login"][0].should contain("a spring.config import in application.yml can override")

    beside = files.merge({"admin/config/application.yml" => "secure:\n  ignored:\n    urls:\n      - /x\n"})
    tags = run_spring_multi_module(beside, {"POST /admin/login" => "admin/src/main/java/com/example/admin/Controller.java:2"})
    tags["POST /admin/login"][0].should contain("config/application.yml beside the module also sets")
  end

  it "counts neither test-scoped nor a dependency's optional Spring Security as on the classpath" do
    tags = run_spring_multi_module(files.merge({
      "tested/pom.xml"                                          => spring_module_pom("tested", ["spring-boot-starter-web"]).sub("</dependencies>", "<dependency><artifactId>spring-security-test</artifactId><scope>test</scope></dependency></dependencies>"),
      "tested/src/main/java/com/example/tested/Controller.java" => controller,
      "optlib/pom.xml"                                          => spring_module_pom("optlib", [] of String).sub("</dependencies>", "<dependency><artifactId>spring-boot-starter-security</artifactId><optional>true</optional></dependency></dependencies>"),
      "optapp/pom.xml"                                          => spring_module_pom("optapp", ["optlib"]),
      "optapp/src/main/java/com/example/optapp/Controller.java" => controller,
    }), {
      "GET /tested" => "tested/src/main/java/com/example/tested/Controller.java:2",
      "GET /optapp" => "optapp/src/main/java/com/example/optapp/Controller.java:2",
    })
    tags["GET /tested"].should be_empty
    tags["GET /optapp"].should be_empty
  end

  it "binds a loop variable only inside its own loop" do
    config = <<-JAVA
      package com.example;

      public class SecurityConfig {
          @Autowired
          private UrlProps urlProps;

          @Bean
          SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(registry -> {
                  for (String url : urlProps.getPermitUrls()) {
                      registry.requestMatchers(url).permitAll();
                  }
                  for (String url : ADMIN_URLS) {
                      registry.requestMatchers(url).hasRole("ADMIN");
                  }
                  registry.anyRequest().authenticated();
              });
              http.csrf(csrf -> {
                  for (String url : urlProps.getCsrfIgnore()) {
                      csrf.ignoringRequestMatchers(url);
                  }
              });
              return http.build();
          }
          private static final String[] ADMIN_URLS = {"/admin/**"};
      }
      JAVA
    props = <<-JAVA
      package com.example;

      @ConfigurationProperties(prefix = "app.security")
      public class UrlProps {
          private List<String> permitUrls;
          private List<String> csrfIgnore;
      }
      JAVA
    tags = run_spring_multi_module({
      "pom.xml"                                       => "<project><artifactId>app</artifactId><dependencies><dependency><artifactId>spring-boot-starter-security</artifactId></dependency></dependencies></project>",
      "src/main/java/com/example/SecurityConfig.java" => config,
      "src/main/java/com/example/UrlProps.java"       => props,
      "src/main/java/com/example/Controller.java"     => controller,
      "src/main/resources/application.yml"            => "app:\n  security:\n    permit-urls: /public/**\n    csrf-ignore: /admin/**\n",
    }, {
      "GET /public/info" => "src/main/java/com/example/Controller.java:2",
      "GET /admin/users" => "src/main/java/com/example/Controller.java:2",
    })
    tags["GET /public/info"].should be_empty
    tags["GET /admin/users"].should eq(["Protected by Spring Security hasRole via requestMatchers(\"/admin/**\")"])
  end

  it "does not report Boot's default chain for an app that declares a permissive chain" do
    config = <<-JAVA
      public class SecurityConfig {
          @Bean
          SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
              http.csrf(c -> c.disable()).authorizeHttpRequests(a -> a.anyRequest().permitAll());
              return http.build();
          }
      }
      JAVA
    tags = run_spring_multi_module({
      "pom.xml"                                       => "<project><artifactId>app</artifactId><dependencies><dependency><artifactId>spring-boot-starter-security</artifactId></dependency></dependencies></project>",
      "src/main/java/com/example/SecurityConfig.java" => config,
      "src/main/java/com/example/Controller.java"     => controller,
    }, {"GET /x" => "src/main/java/com/example/Controller.java:2"})
    tags["GET /x"].should be_empty
  end

  it "reads a handler's own refusal of an anonymous principal" do
    source = <<-JAVA
      public class InfoController {
          @GetMapping(value = {"/info", "/me"})
          public CommonResult info(Principal principal) {
              if (principal == null) {
                  return CommonResult.unauthorized(null);
              }
              return CommonResult.success(principal.getName());
          }

          @GetMapping("/maybe")
          public CommonResult maybe(Principal principal) {
              if (principal == null) {
                  return CommonResult.success(loginFreeFeed());
              }
              return CommonResult.success(principal.getName());
          }

          @PostMapping("/side-effect")
          public CommonResult sideEffect(Principal principal) {
              service.cancel();
              if (principal == null) throw new AccessDeniedException("x");
              return CommonResult.success(null);
          }

          @GetMapping("/redirect")
          public String redirect(Principal principal) {
              if (principal == null) return "redirect:/login";
              return "home";
          }
      }
      JAVA
    kotlin = <<-KOTLIN
      class KController {
          @GetMapping("/k/open")
          fun open(): String = service.secrets()
          @GetMapping("/k/me")
          fun me(principal: Principal?): String {
              if (principal == null) throw ResponseStatusException(HttpStatus.UNAUTHORIZED)
              return principal.name
          }
      }
      KOTLIN
    tags = run_spring_multi_module({"InfoController.java" => source, "KController.kt" => kotlin}, {
      "GET /info"         => "InfoController.java:2",
      "GET /maybe"        => "InfoController.java:10",
      "POST /side-effect" => "InfoController.java:18",
      "GET /redirect"     => "InfoController.java:25",
      "GET /k/open"       => "KController.kt:2",
      "GET /k/me"         => "KController.kt:4",
    })
    tags["GET /info"].should eq(["Protected by in-handler check: refuses an anonymous caller (principal == null)"])
    tags["GET /maybe"].should be_empty
    tags["POST /side-effect"].should be_empty
    tags["GET /redirect"].should eq(["Protected by in-handler check: refuses an anonymous caller (principal == null)"])
    tags["GET /k/open"].should be_empty
    tags["GET /k/me"].should eq(["Protected by in-handler check: refuses an anonymous caller (principal == null)"])
  end
end

def run_spring_endpoints_map(files : Hash(String, String), routes : Hash(String, String)) : Hash(String, Endpoint)
  CodeLocator.instance.clear_all
  root = File.tempname("spring_endpoints_map")
  files.each do |relative, source|
    path = File.join(root, relative)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, source)
    CodeLocator.instance.register_path(path)
  end
  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(root)
  endpoints = routes.map do |route, location|
    method, url = route.split(' ', 2)
    file, line = location.split(':')
    Endpoint.new(url, method, [] of Param, Details.new(PathInfo.new(File.join(root, file), line.to_i)))
  end
  SpringAuthTagger.new(noir_options).perform(endpoints)
  FileUtils.rm_rf(root)
  routes.keys.zip(endpoints).to_h
end

describe "SpringAuthTagger (HandlerInterceptor)" do
  it "detects Java HandlerInterceptor rejecting unauthorized callers with path patterns" do
    interceptor = <<-JAVA
      package com.example.security;

      import javax.servlet.http.HttpServletRequest;
      import javax.servlet.http.HttpServletResponse;
      import org.springframework.web.servlet.HandlerInterceptor;

      public class AuthInterceptor implements HandlerInterceptor {
          @Override
          public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
              String token = request.getHeader("Authorization");
              if (token == null) {
                  response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Unauthorized");
                  return false;
              }
              return true;
          }
      }
      JAVA

    config = <<-JAVA
      package com.example.config;

      import com.example.security.AuthInterceptor;
      import org.springframework.context.annotation.Configuration;
      import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
      import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

      @Configuration
      public class WebConfig implements WebMvcConfigurer {
          @Override
          public void addInterceptors(InterceptorRegistry registry) {
              registry.addInterceptor(new AuthInterceptor())
                      .addPathPatterns("/api/**")
                      .excludePathPatterns("/api/login", "/api/public/**");
          }
      }
      JAVA

    controller = <<-JAVA
      package com.example.controller;

      import org.springframework.web.bind.annotation.*;

      @RestController
      public class ApiController {
          @GetMapping("/api/items")
          public String items() { return "items"; }

          @PostMapping("/api/login")
          public String login() { return "login"; }

          @GetMapping("/api/public/health")
          public String health() { return "ok"; }

          @GetMapping("/other/status")
          public String status() { return "ok"; }
      }
      JAVA

    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/security/AuthInterceptor.java" => interceptor,
      "src/main/java/com/example/config/WebConfig.java"         => config,
      "src/main/java/com/example/controller/ApiController.java" => controller,
    }, {
      "GET /api/items"         => "src/main/java/com/example/controller/ApiController.java:7",
      "POST /api/login"        => "src/main/java/com/example/controller/ApiController.java:10",
      "GET /api/public/health" => "src/main/java/com/example/controller/ApiController.java:13",
      "GET /other/status"      => "src/main/java/com/example/controller/ApiController.java:16",
    })

    endpoints["GET /api/items"].tags.select(&.name.==("auth")).map(&.description).should eq([
      "Protected by Spring HandlerInterceptor AuthInterceptor",
    ])
    endpoints["POST /api/login"].tags.select(&.name.==("auth")).should be_empty
    endpoints["GET /api/public/health"].tags.select(&.name.==("auth")).should be_empty
    endpoints["GET /other/status"].tags.select(&.name.==("auth")).should be_empty
  end

  it "defaults to /** when addPathPatterns is omitted on registered HandlerInterceptor" do
    interceptor = <<-JAVA
      package com.example.security;

      import javax.servlet.http.HttpServletRequest;
      import javax.servlet.http.HttpServletResponse;
      import org.springframework.web.servlet.handler.HandlerInterceptorAdapter;

      public class SessionInterceptor extends HandlerInterceptorAdapter {
          @Override
          public boolean preHandle(HttpServletRequest req, HttpServletResponse res, Object handler) {
              if (req.getSession(false) == null) {
                  res.setStatus(403);
                  return false;
              }
              return true;
          }
      }
      JAVA

    config = <<-JAVA
      package com.example.config;

      import com.example.security.SessionInterceptor;
      import org.springframework.beans.factory.annotation.Autowired;
      import org.springframework.context.annotation.Configuration;
      import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
      import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

      @Configuration
      public class WebConfig implements WebMvcConfigurer {
          @Autowired
          private SessionInterceptor sessionInterceptor;

          @Override
          public void addInterceptors(InterceptorRegistry registry) {
              registry.addInterceptor(sessionInterceptor);
          }
      }
      JAVA

    controller = <<-JAVA
      package com.example.controller;

      import org.springframework.web.bind.annotation.GetMapping;
      import org.springframework.web.bind.annotation.RestController;

      @RestController
      public class DashboardController {
          @GetMapping("/dashboard")
          public String dashboard() { return "dash"; }
      }
      JAVA

    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/security/SessionInterceptor.java"    => interceptor,
      "src/main/java/com/example/config/WebConfig.java"               => config,
      "src/main/java/com/example/controller/DashboardController.java" => controller,
    }, {
      "GET /dashboard" => "src/main/java/com/example/controller/DashboardController.java:7",
    })

    endpoints["GET /dashboard"].tags.select(&.name.==("auth")).map(&.description).should eq([
      "Protected by Spring HandlerInterceptor SessionInterceptor",
    ])
  end

  it "does not tag endpoints for non-rejecting interceptors like LoggingInterceptor" do
    interceptor = <<-JAVA
      package com.example.interceptor;

      import javax.servlet.http.HttpServletRequest;
      import javax.servlet.http.HttpServletResponse;
      import org.springframework.web.servlet.HandlerInterceptor;

      public class LoggingInterceptor implements HandlerInterceptor {
          @Override
          public boolean preHandle(HttpServletRequest req, HttpServletResponse res, Object handler) {
              System.out.println("Path: " + req.getRequestURI());
              return true;
          }
      }
      JAVA

    config = <<-JAVA
      package com.example.config;

      import com.example.interceptor.LoggingInterceptor;
      import org.springframework.context.annotation.Configuration;
      import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
      import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

      @Configuration
      public class WebConfig implements WebMvcConfigurer {
          @Override
          public void addInterceptors(InterceptorRegistry registry) {
              registry.addInterceptor(new LoggingInterceptor()).addPathPatterns("/api/**");
          }
      }
      JAVA

    controller = <<-JAVA
      package com.example.controller;

      import org.springframework.web.bind.annotation.GetMapping;
      import org.springframework.web.bind.annotation.RestController;

      @RestController
      public class ApiController {
          @GetMapping("/api/items")
          public String items() { return "items"; }
      }
      JAVA

    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/interceptor/LoggingInterceptor.java" => interceptor,
      "src/main/java/com/example/config/WebConfig.java"               => config,
      "src/main/java/com/example/controller/ApiController.java"       => controller,
    }, {
      "GET /api/items" => "src/main/java/com/example/controller/ApiController.java:7",
    })

    endpoints["GET /api/items"].tags.select(&.name.==("auth")).should be_empty
  end

  it "detects Kotlin HandlerInterceptor rejecting callers" do
    interceptor = <<-KT
      package com.example.security

      import javax.servlet.http.HttpServletRequest
      import javax.servlet.http.HttpServletResponse
      import org.springframework.web.servlet.HandlerInterceptor

      class KotlinAuthInterceptor : HandlerInterceptor {
          override fun preHandle(request: HttpServletRequest, response: HttpServletResponse, handler: Any): Boolean {
              val token = request.getHeader("Authorization")
              if (token == null) {
                  response.status = 401
                  return false
              }
              return true
          }
      }
      KT

    config = <<-KT
      package com.example.config

      import com.example.security.KotlinAuthInterceptor
      import org.springframework.context.annotation.Configuration
      import org.springframework.web.servlet.config.annotation.InterceptorRegistry
      import org.springframework.web.servlet.config.annotation.WebMvcConfigurer

      @Configuration
      class WebConfig : WebMvcConfigurer {
          override fun addInterceptors(registry: InterceptorRegistry) {
              registry.addInterceptor(KotlinAuthInterceptor()).addPathPatterns("/kapi/**")
          }
      }
      KT

    controller = <<-KT
      package com.example.controller

      import org.springframework.web.bind.annotation.GetMapping
      import org.springframework.web.bind.annotation.RestController

      @RestController
      class KotlinController {
          @GetMapping("/kapi/profile")
          fun profile(): String = "profile"

          @GetMapping("/kpublic/info")
          fun info(): String = "info"
      }
      KT

    endpoints = run_spring_endpoints_map({
      "src/main/kotlin/com/example/security/KotlinAuthInterceptor.kt" => interceptor,
      "src/main/kotlin/com/example/config/WebConfig.kt"               => config,
      "src/main/kotlin/com/example/controller/KotlinController.kt"    => controller,
    }, {
      "GET /kapi/profile" => "src/main/kotlin/com/example/controller/KotlinController.kt:7",
      "GET /kpublic/info" => "src/main/kotlin/com/example/controller/KotlinController.kt:10",
    })

    endpoints["GET /kapi/profile"].tags.select(&.name.==("auth")).map(&.description).should eq([
      "Protected by Spring HandlerInterceptor KotlinAuthInterceptor",
    ])
    endpoints["GET /kpublic/info"].tags.select(&.name.==("auth")).should be_empty
  end

  it "respects multi-module scoping for HandlerInterceptor" do
    module_a_pom = spring_module_pom("service-a", [] of String)
    module_b_pom = spring_module_pom("service-b", [] of String)

    interceptor = <<-JAVA
      package com.example.a;
      import javax.servlet.http.HttpServletRequest;
      import javax.servlet.http.HttpServletResponse;
      import org.springframework.web.servlet.HandlerInterceptor;
      public class InterceptorA implements HandlerInterceptor {
          public boolean preHandle(HttpServletRequest req, HttpServletResponse res, Object h) throws Exception {
              res.sendError(401);
              return false;
          }
      }
      JAVA

    config = <<-JAVA
      package com.example.a;
      import org.springframework.context.annotation.Configuration;
      import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
      import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;
      @Configuration
      public class ConfigA implements WebMvcConfigurer {
          public void addInterceptors(InterceptorRegistry registry) {
              registry.addInterceptor(new InterceptorA()).addPathPatterns("/api/**");
          }
      }
      JAVA

    controller_a = <<-JAVA
      package com.example.a;
      import org.springframework.web.bind.annotation.GetMapping;
      import org.springframework.web.bind.annotation.RestController;
      @RestController
      public class ControllerA {
          @GetMapping("/api/a")
          public String a() { return "a"; }
      }
      JAVA

    controller_b = <<-JAVA
      package com.example.b;
      import org.springframework.web.bind.annotation.GetMapping;
      import org.springframework.web.bind.annotation.RestController;
      @RestController
      public class ControllerB {
          @GetMapping("/api/b")
          public String b() { return "b"; }
      }
      JAVA

    endpoints = run_spring_endpoints_map({
      "pom.xml"                                                 => "<project><artifactId>root</artifactId></project>",
      "service-a/pom.xml"                                       => module_a_pom,
      "service-a/src/main/java/com/example/a/InterceptorA.java" => interceptor,
      "service-a/src/main/java/com/example/a/ConfigA.java"      => config,
      "service-a/src/main/java/com/example/a/ControllerA.java"  => controller_a,
      "service-b/pom.xml"                                       => module_b_pom,
      "service-b/src/main/java/com/example/b/ControllerB.java"  => controller_b,
    }, {
      "GET /api/a" => "service-a/src/main/java/com/example/a/ControllerA.java:6",
      "GET /api/b" => "service-b/src/main/java/com/example/b/ControllerB.java:6",
    })

    endpoints["GET /api/a"].tags.select(&.name.==("auth")).map(&.description).should eq([
      "Protected by Spring HandlerInterceptor InterceptorA",
    ])
    endpoints["GET /api/b"].tags.select(&.name.==("auth")).should be_empty
  end
end

describe "SpringAuthTagger (Meta-annotations)" do
  it "detects Java method-level meta-annotation with @Secured" do
    meta_annotation = <<-JAVA
      package com.example.security;

      import java.lang.annotation.ElementType;
      import java.lang.annotation.Retention;
      import java.lang.annotation.RetentionPolicy;
      import java.lang.annotation.Target;
      import org.springframework.security.access.annotation.Secured;

      @Target({ElementType.METHOD, ElementType.TYPE})
      @Retention(RetentionPolicy.RUNTIME)
      @Secured("ROLE_USER")
      public @interface LoginRequired {
      }
      JAVA

    controller = <<-JAVA
      package com.example.controller;

      import com.example.security.LoginRequired;
      import org.springframework.web.bind.annotation.GetMapping;
      import org.springframework.web.bind.annotation.RestController;

      @RestController
      public class UserController {
          @GetMapping("/profile")
          @LoginRequired
          public String profile() {
              return "profile";
          }
      }
      JAVA

    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/security/LoginRequired.java"    => meta_annotation,
      "src/main/java/com/example/controller/UserController.java" => controller,
    }, {
      "GET /profile" => "src/main/java/com/example/controller/UserController.java:9",
    })

    endpoints["GET /profile"].tags.select(&.name.==("auth")).map(&.description).should eq([
      "Protected by Spring @Secured (@LoginRequired)",
    ])
    endpoints["GET /profile"].tags.map(&.name).should_not contain("admin")
  end

  it "detects Java method-level meta-annotation with @PreAuthorize and admin role" do
    meta_annotation = <<-JAVA
      package com.example.security;

      import java.lang.annotation.ElementType;
      import java.lang.annotation.Retention;
      import java.lang.annotation.RetentionPolicy;
      import java.lang.annotation.Target;
      import org.springframework.security.access.prepost.PreAuthorize;

      @Target({ElementType.METHOD, ElementType.TYPE})
      @Retention(RetentionPolicy.RUNTIME)
      @PreAuthorize("hasRole('ADMIN')")
      public @interface AdminOnly {
      }
      JAVA

    controller = <<-JAVA
      package com.example.controller;

      import com.example.security.AdminOnly;
      import org.springframework.web.bind.annotation.PostMapping;
      import org.springframework.web.bind.annotation.RestController;

      @RestController
      public class AdminController {
          @PostMapping("/admin/reset")
          @AdminOnly
          public String reset() {
              return "reset";
          }
      }
      JAVA

    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/security/AdminOnly.java"         => meta_annotation,
      "src/main/java/com/example/controller/AdminController.java" => controller,
    }, {
      "POST /admin/reset" => "src/main/java/com/example/controller/AdminController.java:9",
    })

    endpoints["POST /admin/reset"].tags.select(&.name.==("auth")).map(&.description).should eq([
      "Protected by Spring @PreAuthorize (@AdminOnly)",
    ])
    endpoints["POST /admin/reset"].tags.map(&.name).should contain("admin")
  end

  it "detects Java class-level meta-annotation with @PreAuthorize and admin role" do
    meta_annotation = <<-JAVA
      package com.example.security;

      import java.lang.annotation.ElementType;
      import java.lang.annotation.Retention;
      import java.lang.annotation.RetentionPolicy;
      import java.lang.annotation.Target;
      import org.springframework.security.access.prepost.PreAuthorize;

      @Target(ElementType.TYPE)
      @Retention(RetentionPolicy.RUNTIME)
      @PreAuthorize("hasAuthority('ROLE_ADMIN')")
      public @interface AdminControllerAnnotation {
      }
      JAVA

    controller = <<-JAVA
      package com.example.controller;

      import com.example.security.AdminControllerAnnotation;
      import org.springframework.web.bind.annotation.GetMapping;
      import org.springframework.web.bind.annotation.RestController;

      @RestController
      @AdminControllerAnnotation
      public class AdminMgmtController {
          @GetMapping("/mgmt/users")
          public String listUsers() {
              return "users";
          }
      }
      JAVA

    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/security/AdminControllerAnnotation.java" => meta_annotation,
      "src/main/java/com/example/controller/AdminMgmtController.java"     => controller,
    }, {
      "GET /mgmt/users" => "src/main/java/com/example/controller/AdminMgmtController.java:10",
    })

    endpoints["GET /mgmt/users"].tags.select(&.name.==("auth")).map(&.description).should eq([
      "Protected by Spring @PreAuthorize (@AdminControllerAnnotation) on the controller class",
    ])
    endpoints["GET /mgmt/users"].tags.map(&.name).should contain("admin")
  end

  it "detects Kotlin meta-annotations with @Secured and @PreAuthorize" do
    meta_annotation = <<-KT
      package com.example.security

      import org.springframework.security.access.annotation.Secured
      import org.springframework.security.access.prepost.PreAuthorize

      @Target(AnnotationTarget.FUNCTION, AnnotationTarget.CLASS)
      @Retention(AnnotationRetention.RUNTIME)
      @Secured("ROLE_USER")
      annotation class UserAuth

      @Target(AnnotationTarget.CLASS)
      @Retention(AnnotationRetention.RUNTIME)
      @PreAuthorize("hasRole('ADMIN')")
      annotation class AdminService
      KT

    controller = <<-KT
      package com.example.controller

      import com.example.security.UserAuth
      import com.example.security.AdminService
      import org.springframework.web.bind.annotation.GetMapping
      import org.springframework.web.bind.annotation.RestController

      @RestController
      class MemberController {
          @GetMapping("/member/settings")
          @UserAuth
          fun settings(): String = "settings"
      }

      @RestController
      @AdminService
      class AdminKController {
          @GetMapping("/admin/audit")
          fun audit(): String = "audit"
      }
      KT

    endpoints = run_spring_endpoints_map({
      "src/main/kotlin/com/example/security/Annotations.kt"   => meta_annotation,
      "src/main/kotlin/com/example/controller/Controllers.kt" => controller,
    }, {
      "GET /member/settings" => "src/main/kotlin/com/example/controller/Controllers.kt:10",
      "GET /admin/audit"     => "src/main/kotlin/com/example/controller/Controllers.kt:18",
    })

    endpoints["GET /member/settings"].tags.select(&.name.==("auth")).map(&.description).should eq([
      "Protected by Spring @Secured (@UserAuth)",
    ])
    endpoints["GET /member/settings"].tags.map(&.name).should_not contain("admin")

    endpoints["GET /admin/audit"].tags.select(&.name.==("auth")).map(&.description).should eq([
      "Protected by Spring @PreAuthorize (@AdminService) on the controller class",
    ])
    endpoints["GET /admin/audit"].tags.map(&.name).should contain("admin")
  end
end
