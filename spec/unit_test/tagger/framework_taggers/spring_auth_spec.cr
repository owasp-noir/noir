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

  it "reads .anonymous(), .denyAll(), and formLogin(...).permitAll() rules" do
    config = <<-JAVA
      @Configuration
      @EnableWebSecurity
      public class SecurityConfig {
          @Bean
          SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
              return http
                  .authorizeHttpRequests(auth -> auth
                      .requestMatchers("/public/**").permitAll()
                      .requestMatchers("/guest/**").anonymous()
                      .requestMatchers("/legacy/**").denyAll()
                      .anyRequest().authenticated())
                  .formLogin(form -> form.loginPage("/signin").permitAll())
                  .build();
          }
      }
      JAVA

    tags = run_spring_security_config({"SecurityConfig.java" => config}, [
      "GET /public/info",
      "GET /guest/welcome",
      "GET /signin",
      "POST /signin",
      "GET /legacy/export",
      "GET /items",
      "POST /items",
    ])

    tags["GET /public/info"].should be_empty
    tags["GET /guest/welcome"].should be_empty
    tags["GET /signin"].should be_empty
    tags["POST /signin"].should be_empty
    tags["GET /legacy/export"].should eq(["Protected by Spring Security denyAll via requestMatchers(\"/legacy/**\")"])
    tags["GET /items"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
    tags["POST /items"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
  end

  it "supports chained and Kotlin DSL formLogin permitAll and Kotlin anonymous/denyAll rules" do
    java_config = <<-JAVA
      public class SecurityConfig extends WebSecurityConfigurerAdapter {
          @Override
          protected void configure(HttpSecurity http) throws Exception {
              http
                  .authorizeRequests()
                      .antMatchers("/anon/**").hasRole("ANONYMOUS")
                      .anyRequest().denyAll()
                      .and()
                  .formLogin()
                      .loginPage("/login-page")
                      .loginProcessingUrl("/do-login")
                      .failureUrl("/login-fail?error=true")
                      .permitAll();
          }
      }
      JAVA

    tags = run_spring_security_config({"SecurityConfig.java" => java_config}, [
      "GET /anon/hello",
      "GET /login-page",
      "POST /do-login",
      "GET /login-fail",
      "GET /other",
    ])
    tags["GET /anon/hello"].should be_empty
    tags["GET /login-page"].should be_empty
    tags["POST /do-login"].should be_empty
    tags["GET /login-fail"].should be_empty
    tags["GET /other"].should eq(["Protected by Spring Security denyAll via anyRequest()"])

    kotlin_config = <<-KOTLIN
      @Configuration
      class KotlinSecurityConfig {
          @Bean
          fun filterChain(http: HttpSecurity): SecurityFilterChain {
              http {
                  authorizeHttpRequests {
                      authorize("/guest/**", anonymous)
                      authorize("/legacy/**", denyAll)
                      authorize(anyRequest, authenticated)
                  }
                  formLogin {
                      loginPage = "/k-signin"
                      permitAll()
                  }
              }
              return http.build()
          }
      }
      KOTLIN

    CodeLocator.instance.clear_all
    tmpdir = File.tempname("spring_kotlin_security")
    Dir.mkdir_p(tmpdir)
    kt_path = File.join(tmpdir, "KotlinSecurityConfig.kt")
    File.write(kt_path, kotlin_config)
    CodeLocator.instance.register_path(kt_path)

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    endpoints = [
      Endpoint.new("/guest/hi", "GET"),
      Endpoint.new("/k-signin", "GET"),
      Endpoint.new("/legacy/old", "GET"),
      Endpoint.new("/items", "GET"),
    ]
    SpringAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints[0].tags.should be_empty
    endpoints[1].tags.should be_empty
    endpoints[2].tags.map(&.description).should eq(["Protected by Spring Security denyAll via authorize(\"/legacy/**\")"])
    endpoints[3].tags.map(&.description).should eq(["Protected by Spring Security authenticated via authorize(anyRequest)"])
  end

  it "records the SecurityConfig path and rule line on chain auth tags and targets java_jaxrs endpoints" do
    SpringAuthTagger.target_techs.should contain("java_jaxrs")

    config = <<-JAVA
      package com.example;

      @Configuration
      @EnableWebSecurity
      public class SecurityConfig {
          @Bean
          SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
              return http
                  .authorizeHttpRequests(auth -> auth
                      .requestMatchers("/legacy/**").denyAll()
                      .anyRequest().authenticated())
                  .build();
          }
      }
      JAVA

    CodeLocator.instance.clear_all
    tmpdir = File.tempname("spring_tag_location")
    Dir.mkdir_p(tmpdir)
    config_path = File.join(tmpdir, "SecurityConfig.java")
    controller_path = File.join(tmpdir, "ItemResource.java")
    File.write(config_path, config)
    File.write(controller_path, "@Path(\"/jaxrs/items\")\npublic class ItemResource {\n  @GET\n  public String list() { return \"[]\"; }\n}\n")
    CodeLocator.instance.register_path(config_path)
    CodeLocator.instance.register_path(controller_path)

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    jaxrs_details = Details.new(PathInfo.new(controller_path, 4))
    jaxrs_details.technology = "java_jaxrs"
    jaxrs_ep = Endpoint.new("/jaxrs/items", "GET", [] of Param, jaxrs_details)

    legacy_details = Details.new(PathInfo.new(controller_path, 4))
    legacy_details.technology = "java_spring"
    legacy_ep = Endpoint.new("/legacy/export", "GET", [] of Param, legacy_details)

    endpoints = [jaxrs_ep, legacy_ep]
    NoirTaggers.run_tagger(endpoints, noir_options, "spring_auth")
    FileUtils.rm_rf(tmpdir)

    jaxrs_tag = endpoints[0].tags.find { |t| t.name == "auth" }.should_not be_nil
    jaxrs_tag.description.should eq("Protected by Spring Security authenticated via anyRequest()")
    jaxrs_tag.path.should eq(config_path)
    jaxrs_tag.line.should eq(11)

    legacy_tag = endpoints[1].tags.find { |t| t.name == "auth" }.should_not be_nil
    legacy_tag.description.should eq("Protected by Spring Security denyAll via requestMatchers(\"/legacy/**\")")
    legacy_tag.path.should eq(config_path)
    legacy_tag.line.should eq(10)
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

  it "reads a 401/403 status or auth exception as the refusal, not a bare return false" do
    interceptors = <<-JAVA
      package com.example.web;

      import org.springframework.web.servlet.HandlerInterceptor;

      public class RateLimitInterceptor implements HandlerInterceptor {
          @Override
          public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
              String token = request.getHeader("X-Api-Token");
              if (!limiter.tryAcquire(token)) {
                  response.setStatus(429);
                  return false;
              }
              return true;
          }
      }

      class SessionInterceptor implements HandlerInterceptor {
          @Override
          public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
              if (request.getSession(false) == null) {
                  response.setStatus(HttpStatus.UNAUTHORIZED.value());
                  return false;
              }
              return true;
          }
      }
      JAVA

    config = <<-JAVA
      package com.example.web;

      @Configuration
      public class WebConfig implements WebMvcConfigurer {
          @Override
          public void addInterceptors(InterceptorRegistry registry) {
              registry.addInterceptor(new RateLimitInterceptor()).addPathPatterns("/api/**");
              registry.addInterceptor(new SessionInterceptor()).addPathPatterns("/account/**");
          }
      }
      JAVA

    controller = <<-JAVA
      package com.example.web;

      @RestController
      public class ItemController {
          @GetMapping("/api/items")
          public String items() { return "ok"; }

          @GetMapping("/account/me")
          public String me() { return "ok"; }
      }
      JAVA

    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/web/Interceptors.java"   => interceptors,
      "src/main/java/com/example/web/WebConfig.java"      => config,
      "src/main/java/com/example/web/ItemController.java" => controller,
    }, {
      "GET /api/items"  => "src/main/java/com/example/web/ItemController.java:5",
      "GET /account/me" => "src/main/java/com/example/web/ItemController.java:8",
    })

    endpoints["GET /api/items"].tags.should be_empty
    tag = endpoints["GET /account/me"].tags.should_not be_empty
    tag.map(&.description).should eq(["Protected by Spring HandlerInterceptor SessionInterceptor"])
    tag[0].path.not_nil!.ends_with?("src/main/java/com/example/web/WebConfig.java").should be_true
    tag[0].line.should eq(8)
  end

  it "keeps each Kotlin registration's path patterns to its own interceptor" do
    interceptors = <<-KT
      package com.example.web

      class AuthInterceptor : HandlerInterceptor {
          override fun preHandle(request: HttpServletRequest, response: HttpServletResponse, handler: Any): Boolean {
              if (request.getSession(false) == null) {
                  response.status = 401
                  return false
              }
              return true
          }
      }

      class LoggingInterceptor : HandlerInterceptor {
          override fun preHandle(request: HttpServletRequest, response: HttpServletResponse, handler: Any): Boolean {
              log.info(request.requestURI)
              return true
          }
      }
      KT

    config = <<-KT
      package com.example.web

      @Configuration
      class WebConfig : WebMvcConfigurer {
          override fun addInterceptors(registry: InterceptorRegistry) {
              registry.addInterceptor(AuthInterceptor()).addPathPatterns("/kapi/**")
              registry.addInterceptor(LoggingInterceptor()).addPathPatterns("/kpublic/**")
          }
      }
      KT

    controller = <<-KT
      package com.example.web

      @RestController
      class KotlinController {
          @GetMapping("/kapi/profile")
          fun profile(): String = "profile"

          @GetMapping("/kpublic/info")
          fun info(): String = "info"
      }
      KT

    endpoints = run_spring_endpoints_map({
      "src/main/kotlin/com/example/web/Interceptors.kt"     => interceptors,
      "src/main/kotlin/com/example/web/WebConfig.kt"        => config,
      "src/main/kotlin/com/example/web/KotlinController.kt" => controller,
    }, {
      "GET /kapi/profile" => "src/main/kotlin/com/example/web/KotlinController.kt:5",
      "GET /kpublic/info" => "src/main/kotlin/com/example/web/KotlinController.kt:8",
    })

    endpoints["GET /kapi/profile"].tags.map(&.description).should eq([
      "Protected by Spring HandlerInterceptor AuthInterceptor",
    ])
    endpoints["GET /kpublic/info"].tags.should be_empty
  end
end

describe "SpringAuthTagger (Meta-annotations)" do
  it "counts @PostAuthorize as a guard on reads only, since it runs after the handler" do
    meta_annotation = <<-JAVA
      package com.example.security;

      @Target(ElementType.METHOD)
      @Retention(RetentionPolicy.RUNTIME)
      @PostAuthorize("returnObject.owner == authentication.name")
      public @interface OwnerOnly {
      }
      JAVA

    controller = <<-JAVA
      package com.example.controller;

      @RestController
      public class DocController {
          @PostAuthorize("returnObject.owner == authentication.name")
          @GetMapping("/docs/{id}")
          public Doc get(@PathVariable Long id) { return repo.find(id); }

          @PostAuthorize("returnObject.owner == authentication.name")
          @DeleteMapping("/docs/{id}")
          public Doc delete(@PathVariable Long id) { return repo.delete(id); }

          @OwnerOnly
          @PutMapping("/docs/{id}")
          public Doc update(@PathVariable Long id) { return repo.save(id); }
      }
      JAVA

    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/security/OwnerOnly.java"       => meta_annotation,
      "src/main/java/com/example/controller/DocController.java" => controller,
    }, {
      "GET /docs/{id}"    => "src/main/java/com/example/controller/DocController.java:6",
      "DELETE /docs/{id}" => "src/main/java/com/example/controller/DocController.java:10",
      "PUT /docs/{id}"    => "src/main/java/com/example/controller/DocController.java:14",
    })

    endpoints["GET /docs/{id}"].tags.map(&.description).should eq(["Protected by Spring @PostAuthorize"])
    endpoints["DELETE /docs/{id}"].tags.should be_empty
    endpoints["PUT /docs/{id}"].tags.should be_empty
  end

  it "does not read a longer class annotation as a meta-annotation that prefixes it" do
    meta_annotation = <<-JAVA
      package com.example.security;

      @Target(ElementType.TYPE)
      @Retention(RetentionPolicy.RUNTIME)
      @PreAuthorize("hasRole('ADMIN')")
      public @interface Admin {
      }
      JAVA

    controller = <<-JAVA
      package com.example.controller;

      @AdminApi
      @RestController
      public class DocsController {
          @GetMapping("/docs")
          public String docs() { return "docs"; }
      }
      JAVA

    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/security/Admin.java"            => meta_annotation,
      "src/main/java/com/example/controller/DocsController.java" => controller,
    }, {
      "GET /docs" => "src/main/java/com/example/controller/DocsController.java:6",
    })

    endpoints["GET /docs"].tags.should be_empty
  end

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
  end

  it "detects Java method-level meta-annotation with @PreAuthorize" do
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

    endpoints["POST /admin/reset"].tags.map(&.description).should eq([
      "Protected by Spring @PreAuthorize (@AdminOnly)",
    ])
  end

  it "detects Java class-level meta-annotation with @PreAuthorize" do
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

    endpoints["GET /mgmt/users"].tags.map(&.description).should eq([
      "Protected by Spring @PreAuthorize (@AdminControllerAnnotation) on the controller class",
    ])
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

    endpoints["GET /admin/audit"].tags.map(&.description).should eq([
      "Protected by Spring @PreAuthorize (@AdminService) on the controller class",
    ])
  end
end

# Auth tag descriptions per "METHOD /path" for servlet filter sources;
# every route points at the controller written as `Controller.{ext}`.
def servlet_filter_auth(files : Hash(String, String), routes : Array(String)) : Hash(String, Array(String))
  map = routes.to_h { |route| {route, files.keys.find!(&.includes?("Controller")) + ":1"} }
  run_spring_endpoints_map(files, map).transform_values { |endpoint| endpoint.tags.select(&.name.==("auth")).map(&.description) }
end

describe "SpringAuthTagger (servlet filter)" do
  kotlin_controller = <<-KOTLIN
    @RestController
    class AdminController {
        @DeleteMapping("/admin/users/{id}")
        fun delete(@PathVariable id: String): String = "deleted"
    }
    KOTLIN

  java_controller = <<-JAVA
    @RestController
    public class AdminController {
        @DeleteMapping("/admin/users/{id}")
        public String delete(@PathVariable String id) { return "deleted"; }
    }
    JAVA

  it "guards the routes a FilterRegistrationBean maps a refusing OncePerRequestFilter to (#3255)" do
    filter = <<-KOTLIN
      class ApiKeyFilter(private val key: String) : OncePerRequestFilter() {
          override fun shouldNotFilter(request: HttpServletRequest): Boolean =
              !request.servletPath.startsWith("/admin/")

          override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {
              if (request.getHeader("X-Api-Key") != key) {
                  response.status = 401
                  return
              }
              chain.doFilter(request, response)
          }
      }

      @Configuration
      class FilterConfig {
          @Bean
          fun apiKeyFilter(): FilterRegistrationBean<ApiKeyFilter> =
              FilterRegistrationBean(ApiKeyFilter("secret")).apply { addUrlPatterns("/admin/*") }
      }
      KOTLIN

    tags = servlet_filter_auth({"src/main/kotlin/app/ApiKeyFilter.kt" => filter, "src/main/kotlin/app/Controller.kt" => kotlin_controller},
      ["DELETE /admin/users/{id}", "GET /items/{id}", "GET /admin"])
    tags["DELETE /admin/users/{id}"].should eq(["Protected by Servlet filter ApiKeyFilter on /admin/* (refuses with 401)"])
    tags["GET /items/{id}"].should be_empty
    # `/admin` is mapped by `/admin/*` but `shouldNotFilter` skips it: it does not start with "/admin/".
    tags["GET /admin"].should be_empty
  end

  it "scopes a @Component filter (mapped to every request) by its shouldNotFilter block" do
    filter = <<-JAVA
      @Component
      public class TokenFilter extends OncePerRequestFilter {
          @Override
          protected boolean shouldNotFilter(HttpServletRequest request) {
              String path = request.getRequestURI();
              if (path.startsWith("/public/")) return true;
              return path.equals("/login");
          }

          @Override
          protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
              String token = request.getHeader("Authorization");
              if (token == null || !tokens.isValid(token)) {
                  response.sendError(HttpServletResponse.SC_UNAUTHORIZED);
                  return;
              }
              chain.doFilter(request, response);
          }
      }
      JAVA

    tags = servlet_filter_auth({"src/main/java/app/TokenFilter.java" => filter, "src/main/java/app/Controller.java" => java_controller},
      ["DELETE /admin/users/{id}", "GET /public/docs", "POST /login"])
    tags["DELETE /admin/users/{id}"].should eq(["Protected by Servlet filter TokenFilter on /* (refuses with 401)"])
    tags["GET /public/docs"].should be_empty
    tags["POST /login"].should be_empty
  end

  it "reads Java registrations: addUrlPatterns, setUrlPatterns(List.of(...)) and a GenericFilterBean / Filter refusal" do
    filters = <<-JAVA
      public class AdminKeyFilter extends GenericFilterBean {
          @Override
          public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain) throws IOException, ServletException {
              String key = ((HttpServletRequest) req).getHeader("X-Admin-Key");
              if (!"s3cret".equals(key)) {
                  ((HttpServletResponse) res).sendError(401);
                  return;
              }
              chain.doFilter(req, res);
          }
      }

      public class SessionFilter implements Filter {
          @Override
          public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain) throws IOException, ServletException {
              HttpServletRequest request = (HttpServletRequest) req;
              if (request.getSession(false) == null) {
                  ((HttpServletResponse) res).setStatus(403);
                  return;
              }
              chain.doFilter(req, res);
          }
      }

      @Configuration
      public class FilterConfig {
          @Bean
          public FilterRegistrationBean<AdminKeyFilter> adminKeyFilter() {
              FilterRegistrationBean<AdminKeyFilter> registration = new FilterRegistrationBean<>();
              registration.setFilter(new AdminKeyFilter());
              registration.addUrlPatterns("/admin/*");
              return registration;
          }

          @Bean
          public FilterRegistrationBean<SessionFilter> sessionFilter() {
              FilterRegistrationBean<SessionFilter> registration = new FilterRegistrationBean<>(new SessionFilter());
              registration.setUrlPatterns(List.of("/account/*", "/orders"));
              return registration;
          }
      }
      JAVA

    tags = servlet_filter_auth({"src/main/java/app/FilterConfig.java" => filters, "src/main/java/app/Controller.java" => java_controller},
      ["DELETE /admin/users/{id}", "GET /account/profile", "GET /orders", "GET /orders/1", "GET /items"])
    tags["DELETE /admin/users/{id}"].should eq(["Protected by Servlet filter AdminKeyFilter on /admin/* (refuses with 401)"])
    tags["GET /account/profile"].should eq(["Protected by Servlet filter SessionFilter on /account/* (refuses with 403)"])
    tags["GET /orders"].should eq(["Protected by Servlet filter SessionFilter on /orders (refuses with 403)"])
    tags["GET /orders/1"].should be_empty
    tags["GET /items"].should be_empty
  end

  it "reads @WebFilter urlPatterns when @ServletComponentScan is on, and a refusal in a helper method" do
    filter = <<-JAVA
      @WebFilter(urlPatterns = {"/admin/*"})
      public class AdminFilter extends OncePerRequestFilter {
          @Override
          protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
              if (request.getUserPrincipal() == null) {
                  deny(response);
                  return;
              }
              chain.doFilter(request, response);
          }

          private void deny(HttpServletResponse response) throws IOException {
              response.setStatus(HttpServletResponse.SC_FORBIDDEN);
          }
      }
      JAVA
    app = <<-JAVA
      @SpringBootApplication
      @ServletComponentScan
      public class App {
          public static void main(String[] args) { SpringApplication.run(App.class, args); }
      }
      JAVA

    files = {"build.gradle" => "", "src/main/java/app/AdminFilter.java" => filter, "src/main/java/app/Controller.java" => java_controller}
    # A Boot app registers @WebFilter classes only under @ServletComponentScan.
    unscanned = servlet_filter_auth(files.merge({"src/main/java/app/App.java" => app.sub("@ServletComponentScan\n", "")}), ["DELETE /admin/users/{id}"])
    unscanned["DELETE /admin/users/{id}"].should be_empty
    tags = servlet_filter_auth(files.merge({"src/main/java/app/App.java" => app}), ["DELETE /admin/users/{id}", "GET /items"])
    tags["DELETE /admin/users/{id}"].should eq(["Protected by Servlet filter AdminFilter on /admin/* (refuses with 403)"])
    tags["GET /items"].should be_empty
  end

  it "keeps the valid-credential pass-through and a literal whitelist (Kotlin `in`)" do
    filter = <<-KOTLIN
      class ApiKeyFilter(private val props: Props) : OncePerRequestFilter() {
          private val open = setOf("/admin/health")

          override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, filterChain: FilterChain) {
              if (request.requestURI in open || matches(request.getHeader(API_KEY_HEADER))) {
                  filterChain.doFilter(request, response)
                  return
              }
              problems.write(response, HttpStatus.UNAUTHORIZED)
          }
      }

      @Configuration
      class ApiKeyConfig {
          @Bean
          fun apiKeyFilter(props: Props) = FilterRegistrationBean(ApiKeyFilter(props)).apply {
              addUrlPatterns("/admin/*")
          }
      }
      KOTLIN

    tags = servlet_filter_auth({"src/main/kotlin/app/ApiKeyFilter.kt" => filter, "src/main/kotlin/app/Controller.kt" => kotlin_controller},
      ["DELETE /admin/users/{id}", "GET /admin/health"])
    tags["DELETE /admin/users/{id}"].should eq(["Protected by Servlet filter ApiKeyFilter on /admin/* (refuses with 401)"])
    tags["GET /admin/health"].should be_empty
  end

  it "does not count filters that never refuse, refuse for another reason, or let anonymous callers through" do
    filters = <<-JAVA
      @Component
      public class LoggingFilter extends OncePerRequestFilter {
          @Override
          protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
              log.info("{} {} auth={}", request.getMethod(), request.getRequestURI(), request.getHeader("Authorization"));
              chain.doFilter(request, response);
          }
      }

      @Component
      public class RateLimitFilter extends OncePerRequestFilter {
          @Override
          protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
              if (!buckets.tryConsume(request.getHeader("X-Api-Key"))) {
                  response.setStatus(429);
                  return;
              }
              chain.doFilter(request, response);
          }
      }

      @Component
      public class CsrfHeaderFilter extends OncePerRequestFilter {
          @Override
          protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
              if (request.getHeader("X-CSRF-Token") == null) {
                  response.sendError(HttpServletResponse.SC_FORBIDDEN);
                  return;
              }
              chain.doFilter(request, response);
          }
      }

      @Component
      public class RefererCheck implements Filter {
          @Override
          public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain) throws IOException, ServletException {
              if (((HttpServletRequest) req).getHeader("Referer") == null) {
                  ((HttpServletResponse) res).sendError(403);
                  return;
              }
              chain.doFilter(req, res);
          }
      }

      @Component
      public class JwtFilter extends OncePerRequestFilter {
          @Override
          protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
              String header = request.getHeader("Authorization");
              if (header == null || !header.startsWith("Bearer ")) {
                  chain.doFilter(request, response);
                  return;
              }
              if (!jwt.valid(header.substring(7))) {
                  response.sendError(HttpServletResponse.SC_UNAUTHORIZED);
                  return;
              }
              chain.doFilter(request, response);
          }
      }

      @Component
      public class SessionExpiryFilter extends OncePerRequestFilter {
          @Override
          protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
              if (hasSessionCookie(request.getCookies())) {
                  response.sendError(HttpServletResponse.SC_UNAUTHORIZED);
                  return;
              }
              chain.doFilter(request, response);
          }
      }

      @Component
      public class WhitelistFilter extends OncePerRequestFilter {
          @Override
          protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
              if (isPublic(request.getRequestURI())) {
                  chain.doFilter(request, response);
                  return;
              }
              if (request.getSession(false) == null) {
                  response.sendError(401);
                  return;
              }
              chain.doFilter(request, response);
          }
      }
      JAVA

    tags = servlet_filter_auth({"src/main/java/app/Filters.java" => filters, "src/main/java/app/Controller.java" => java_controller}, ["DELETE /admin/users/{id}"])
    tags["DELETE /admin/users/{id}"].should be_empty
  end

  it "does not count a registration it cannot read or one that is disabled" do
    filters = <<-JAVA
      @Component
      public class KeyFilter extends OncePerRequestFilter {
          @Override
          protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
              if (request.getHeader("X-Api-Key") == null) {
                  response.sendError(401);
                  return;
              }
              chain.doFilter(request, response);
          }
      }

      public class PrefixKeyFilter extends OncePerRequestFilter {
          @Override
          protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
              if (request.getHeader("X-Api-Key") == null) {
                  response.sendError(401);
                  return;
              }
              chain.doFilter(request, response);
          }
      }

      @Configuration
      public class FilterConfig {
          @Bean
          public FilterRegistrationBean<KeyFilter> keyFilter(KeyFilter filter) {
              FilterRegistrationBean<KeyFilter> registration = new FilterRegistrationBean<>(filter);
              registration.setEnabled(false);
              return registration;
          }

          @Bean
          public FilterRegistrationBean<PrefixKeyFilter> prefixKeyFilter() {
              FilterRegistrationBean<PrefixKeyFilter> registration = new FilterRegistrationBean<>();
              registration.setFilter(new PrefixKeyFilter());
              registration.addUrlPatterns(Constants.ADMIN_PREFIX + "/*");
              return registration;
          }
      }
      JAVA

    tags = servlet_filter_auth({"src/main/java/app/FilterConfig.java" => filters, "src/main/java/app/Controller.java" => java_controller}, ["DELETE /admin/users/{id}"])
    tags["DELETE /admin/users/{id}"].should be_empty
  end
end

# The adversarial cases of the #3255 review: a Gradle Boot app with
# `AdminController` (GET/POST /admin/users, GET /items) and one filter file.
REVIEW_JAVA_CONTROLLER = <<-JAVA
  @RestController
  public class AdminController {
      @GetMapping("/admin/users")
      public String list() { return "x"; }
      @PostMapping("/admin/users")
      public String create() { return "x"; }
      @GetMapping("/items")
      public String items() { return "x"; }
  }
  JAVA

REVIEW_FILTERS = {
  "c01_post_only" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    @Component
    public class ApiKeyFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            String key = request.getHeader("X-Api-Key");
            if ("POST".equals(request.getMethod()) && key == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "c02_present_and_wrong" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    @Component
    public class ApiKeyFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            String key = request.getHeader("X-Api-Key");
            if (key != null && !key.equals("secret")) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "c03_catch_downstream" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    @Component
    public class AuthErrorFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            log.debug("auth header {}", request.getHeader("Authorization"));
            try {
                chain.doFilter(request, response);
            } catch (AuthenticationException e) {
                response.sendError(HttpServletResponse.SC_UNAUTHORIZED);
            }
        }
    }
    JAVA
  "c05_antmatcher_skip" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    @Component
    public class JwtFilter extends OncePerRequestFilter {
        private final AntPathMatcher matcher = new AntPathMatcher();
        private static final List<String> OPEN = List.of("/admin/**");
        @Override
        protected boolean shouldNotFilter(HttpServletRequest request) {
            return OPEN.stream().anyMatch(p -> matcher.match(p, request.getServletPath()));
        }
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            String token = request.getHeader("Authorization");
            if (token == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "c05b_skip_requestcontext" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    @Component
    public class JwtFilter extends OncePerRequestFilter {
        @Override
        protected boolean shouldNotFilter(HttpServletRequest request) {
            return skipper.isOpen(RequestContextHolder.currentRequestAttributes());
        }
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            String token = request.getHeader("Authorization");
            if (token == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "c05c_skip_regex" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    @Component
    public class JwtFilter extends OncePerRequestFilter {
        @Override
        protected boolean shouldNotFilter(HttpServletRequest request) {
            return request.getRequestURI().matches("/admin/.*");
        }
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            String token = request.getHeader("Authorization");
            if (token == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "c10_unregistered_with_bean_of_other" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    public class ApiKeyFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            if (request.getHeader("X-Api-Key") == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    @Configuration
    class Other {
        @Bean
        public ApiKeyFilter apiKeyFilterForTests() { return null; }
    }
    JAVA
  "c11_disabled_registration_var" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    @Component
    public class JwtFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            if (request.getHeader("Authorization") == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    @Configuration
    class FilterConfig {
        @Bean
        public FilterRegistrationBean<JwtFilter> reg(JwtFilter f) {
            FilterRegistrationBean<JwtFilter> r = new FilterRegistrationBean<>(f);
            r.setEnabled(false);
            return r;
        }
    }
    JAVA
  "c12_forbidden_named_predicate" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    @Component
    public class AuditFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            String token = request.getHeader("Authorization");
            if (!isForbiddenPathLogged(request.getRequestURI())) {
                log.info("path {}", request.getRequestURI());
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "c13_refusal_path_conditioned" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    @Component
    public class ApiKeyFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            String key = request.getHeader("X-Api-Key");
            if (request.getRequestURI().startsWith("/internal") && key == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "c14_missing_passes_first_branch" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    @Component
    public class ApiKeyFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            String key = request.getHeader("X-Api-Key");
            if (key == null) {
                chain.doFilter(request, response);
            } else if (!valid(key)) {
                response.sendError(401);
            } else {
                chain.doFilter(request, response);
            }
        }
    }
    JAVA
  "k01_when_present_wrong" => {"src/main/kotlin/app/Filter.kt", <<-KOTLIN},
    package app
    @Component
    class ApiKeyFilter : OncePerRequestFilter() {
        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {
            val token = request.getHeader("Authorization")
            when {
                token != null && !valid(token) -> response.sendError(401)
                else -> chain.doFilter(request, response)
            }
        }
    }
    KOTLIN
  "k03_method_only" => {"src/main/kotlin/app/Filter.kt", <<-KOTLIN},
    package app
    @Component
    class ApiKeyFilter : OncePerRequestFilter() {
        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {
            if (request.method == "POST" && request.getHeader("X-Api-Key") == null) {
                response.status = 401
                return
            }
            chain.doFilter(request, response)
        }
    }
    KOTLIN
  "k04_try_catch" => {"src/main/kotlin/app/Filter.kt", <<-KOTLIN},
    package app
    @Component
    class AuthErrorFilter : OncePerRequestFilter() {
        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {
            logger.debug(request.getHeader("Authorization"))
            try {
                chain.doFilter(request, response)
            } catch (e: AuthException) {
                response.status = 401
            }
        }
    }
    KOTLIN
  "k05_skip_any" => {"src/main/kotlin/app/Filter.kt", <<-KOTLIN},
    package app
    @Component
    class ApiKeyFilter : OncePerRequestFilter() {
        private val excluded = listOf("/admin")
        override fun shouldNotFilter(request: HttpServletRequest): Boolean =
            excluded.any { request.servletPath.startsWith(it) }
        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {
            if (request.getHeader("X-Api-Key") == null) {
                response.status = 401
                return
            }
            chain.doFilter(request, response)
        }
    }
    KOTLIN
  "c04_config_gated" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    @Component
    public class ApiKeyFilter extends OncePerRequestFilter {
        @Value("${apikey.enabled:false}")
        private boolean enabled;
        @Override
        protected boolean shouldNotFilter(HttpServletRequest request) {
            return !enabled;
        }
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            String key = request.getHeader("X-Api-Key");
            if (key == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "c04b_config_gated_inline" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    @Component
    public class ApiKeyFilter extends OncePerRequestFilter {
        @Value("${apikey.enabled:false}")
        private boolean enabled;
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            if (!enabled) {
                chain.doFilter(request, response);
                return;
            }
            String key = request.getHeader("X-Api-Key");
            if (key == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "c07_enabled_property" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    public class ApiKeyFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            if (request.getHeader("X-Api-Key") == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    @Configuration
    class FilterConfig {
        @Value("${apikey.enabled}") boolean enabled;
        @Bean
        public FilterRegistrationBean<ApiKeyFilter> reg() {
            FilterRegistrationBean<ApiKeyFilter> r = new FilterRegistrationBean<>(new ApiKeyFilter());
            r.addUrlPatterns("/admin/*");
            r.setEnabled(enabled);
            return r;
        }
    }
    JAVA
  "c08_conditional_bean" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    public class ApiKeyFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            if (request.getHeader("X-Api-Key") == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    @Configuration
    class FilterConfig {
        @Bean
        @ConditionalOnProperty(name = "apikey.enabled", havingValue = "true")
        public FilterRegistrationBean<ApiKeyFilter> reg() {
            FilterRegistrationBean<ApiKeyFilter> r = new FilterRegistrationBean<>(new ApiKeyFilter());
            r.addUrlPatterns("/admin/*");
            return r;
        }
    }
    JAVA
  "c06_context_path" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    public class ApiKeyFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            if (request.getHeader("X-Api-Key") == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    @Configuration
    class FilterConfig {
        @Bean
        public FilterRegistrationBean<ApiKeyFilter> reg() {
            FilterRegistrationBean<ApiKeyFilter> r = new FilterRegistrationBean<>(new ApiKeyFilter());
            r.addUrlPatterns("/admin/*");
            r.setOrder(1);
            return r;
        }
    }
    JAVA
  "c09_component_and_registration" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;

    @Component
    public class ApiKeyFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            if (request.getHeader("X-Api-Key") == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    @Configuration
    class FilterConfig {
        @Bean
        public FilterRegistrationBean<ApiKeyFilter> reg() {
            FilterRegistrationBean<ApiKeyFilter> r = new FilterRegistrationBean<>(new ApiKeyFilter());
            r.addUrlPatterns("/admin/*");
            return r;
        }
    }
    JAVA
  "k02_when_missing_refused" => {"src/main/kotlin/app/Filter.kt", <<-KOTLIN},
    package app
    @Component
    class ApiKeyFilter : OncePerRequestFilter() {
        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {
            val token = request.getHeader("Authorization")
            when (token) {
                null -> response.sendError(401)
                else -> chain.doFilter(request, response)
            }
        }
    }
    KOTLIN
  "k06_issue_repro" => {"src/main/kotlin/app/Filter.kt", <<-KOTLIN},
    package app
    class ApiKeyFilter(private val key: String) : OncePerRequestFilter() {
        override fun shouldNotFilter(request: HttpServletRequest): Boolean =
            !request.servletPath.startsWith("/admin/")

        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {
            if (request.getHeader("X-Api-Key") != key) {
                response.status = 401
                return
            }
            chain.doFilter(request, response)
        }
    }

    @Configuration
    class FilterConfig {
        @Bean
        fun apiKeyFilter(): FilterRegistrationBean<ApiKeyFilter> =
            FilterRegistrationBean(ApiKeyFilter("secret")).apply { addUrlPatterns("/admin/*") }
    }
    KOTLIN
}

# Auth tag descriptions of the review app's routes, with `filter` in place
# (`extra`: more files; `prefix`: the routes' context path).
def review_case(name : String, extra = {} of String => String, prefix = "") : Hash(String, Array(String))
  path, source = REVIEW_FILTERS[name]? || REVIEW_FILTERS2[name]
  files = {"build.gradle" => "plugins { id 'org.springframework.boot' version '3.2.0'; id 'java' }\n",
           "src/main/java/app/App.java" => "@SpringBootApplication\npublic class App { public static void main(String[] a) { SpringApplication.run(App.class, a); } }\n",
           "src/main/java/app/AdminController.java" => REVIEW_JAVA_CONTROLLER, path => source}.merge(extra)
  routes = {"GET #{prefix}/admin/users" => "src/main/java/app/AdminController.java:4", "POST #{prefix}/admin/users" => "src/main/java/app/AdminController.java:6",
            "GET #{prefix}/items" => "src/main/java/app/AdminController.java:8"}
  run_spring_endpoints_map(files, routes).transform_values { |endpoint| endpoint.tags.select(&.name.==("auth")).map(&.description) }
end

# A Maven reactor of Boot apps: `modules` maps each module to its
# dependencies and `{path => source}` under `src/main/java`.
def review_reactor(modules : Hash(String, {Array(String), Hash(String, String)})) : Hash(String, Array(String))
  files = {"pom.xml" => "<project><groupId>g</groupId><artifactId>parent</artifactId><packaging>pom</packaging>\n<modules>#{modules.keys.map { |m| "<module>#{m}</module>" }.join}</modules></project>\n"}
  routes = {} of String => String
  modules.each do |name, (deps, sources)|
    dependencies = deps.map { |dep| "<dependency><groupId>g</groupId><artifactId>#{dep}</artifactId></dependency>" }.join
    files["#{name}/pom.xml"] = "<project><parent><groupId>g</groupId><artifactId>parent</artifactId></parent>\n<artifactId>#{name}</artifactId>\n<dependencies><dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>#{dependencies}</dependencies></project>\n"
    sources.each { |path, source| files["#{name}/src/main/java/#{path}"] = source }
    next if name == "lib"
    pkg = name.delete('-')
    files["#{name}/src/main/java/#{pkg}/App.java"] = "package #{pkg};\n@SpringBootApplication\npublic class App { public static void main(String[] a) { SpringApplication.run(App.class, a); } }\n"
    files["#{name}/src/main/java/#{pkg}/Ctrl.java"] = "package #{pkg};\n@RestController\npublic class Ctrl {\n    @GetMapping(\"/#{pkg}/admin/users\")\n    public String list() { return \"x\"; }\n}\n"
    routes["GET /#{pkg}/admin/users"] = "#{name}/src/main/java/#{pkg}/Ctrl.java:3"
  end
  run_spring_endpoints_map(files, routes).transform_values { |endpoint| endpoint.tags.select(&.name.==("auth")).map(&.description) }
end

def review_filter(pkg : String, name : String, ann = "", refusing = true) : String
  check = refusing ? "if (request.getHeader(\"Authorization\") == null) {\n            response.sendError(401);\n            return;\n        }" : "log.info(\"auth={}\", request.getHeader(\"Authorization\"));"
  "package #{pkg};\n#{ann}\npublic class #{name} extends OncePerRequestFilter {\n    @Override\n    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {\n        #{check}\n        chain.doFilter(request, response);\n    }\n}\n"
end

describe "SpringAuthTagger (servlet filter review cases)" do
  it "emits no guard where an anonymous caller can reach the handler or the reading is unclear" do
    %w[c01_post_only c02_present_and_wrong c03_catch_downstream c05_antmatcher_skip c05b_skip_requestcontext c05c_skip_regex c10_unregistered_with_bean_of_other c11_disabled_registration_var c12_forbidden_named_predicate c13_refusal_path_conditioned c14_missing_passes_first_branch k01_when_present_wrong k03_method_only k04_try_catch k05_skip_any].each do |name|
      review_case(name).each do |route, tags|
        {name, route, tags}.should eq({name, route, [] of String})
      end
    end
  end

  it "notes the setting that can lift a config-gated filter" do
    {"c04_config_gated"         => "Protected by Servlet filter ApiKeyFilter on /* (refuses with 401); a setting can lift it: it hands the request on unchecked when `!enabled`",
     "c04b_config_gated_inline" => "Protected by Servlet filter ApiKeyFilter on /* (refuses with 401); a setting can lift it: it hands the request on unchecked when `!enabled`",
     "c07_enabled_property"     => "Protected by Servlet filter ApiKeyFilter on /admin/* (refuses with 401); a setting can lift it: its registration is enabled by `setEnabled(enabled)`",
     "c08_conditional_bean"     => "Protected by Servlet filter ApiKeyFilter on /admin/* (refuses with 401); a setting can lift it: it is registered only under `@ConditionalOnProperty(name = \"apikey.enabled\", havingValue = \"true\")`"}.each do |name, description|
      tags = review_case(name)
      tags["GET /admin/users"].should eq([description])
      tags["GET /items"].should eq(description.includes?("on /*") ? [description] : [] of String)
    end
  end

  it "guards a filter that refuses a missing credential, matching below the context path" do
    review_case("k02_when_missing_refused").values.should eq([["Protected by Servlet filter ApiKeyFilter on /* (refuses with 401)"]] * 3)
    issue = review_case("k06_issue_repro")
    issue["GET /admin/users"].should eq(["Protected by Servlet filter ApiKeyFilter on /admin/* (refuses with 401)"])
    issue["GET /items"].should be_empty
    # A `@Component` that is also registered is read as its registration's patterns.
    review_case("c09_component_and_registration")["GET /items"].should be_empty

    properties = "src/main/resources/application.properties"
    context = review_case("c06_context_path", {properties => "server.servlet.context-path=/api\n"}, "/api")
    context["GET /api/admin/users"].should eq(["Protected by Servlet filter ApiKeyFilter on /admin/* (refuses with 401)"])
    context["GET /api/items"].should be_empty
    # The filter's `/admin/*` is below the context path, not the context path itself.
    same = review_case("c06_context_path", {properties => "server.servlet.context-path=/admin\n"}, "/admin")
    same["GET /admin/items"].should be_empty
    same["GET /admin/admin/users"].should eq(["Protected by Servlet filter ApiKeyFilter on /admin/* (refuses with 401)"])
  end

  it "skips filters under test sources" do
    files = {"src/test/java/app/TestAuthFilter.java" => review_filter("app", "TestAuthFilter", "@Component")}
    review_case("c12_forbidden_named_predicate", files).values.flatten.should be_empty
  end

  it "keeps filters, beans and @ServletComponentScan to the app that declares them" do
    registration = ->(pkg : String, name : String) { "package #{pkg};\n@Configuration\npublic class FilterConfig {\n    @Bean\n    public FilterRegistrationBean<#{name}> reg() {\n        FilterRegistrationBean<#{name}> r = new FilterRegistrationBean<>(new #{name}());\n        r.addUrlPatterns(\"/*\");\n        return r;\n    }\n}\n" }
    {"app-a" => "app-b", "app-b" => "app-a"}.each do |refusing, logging|
      tags = review_reactor({
        refusing => {[] of String, {"#{refusing.delete('-')}/AuthFilter.java" => review_filter(refusing.delete('-'), "AuthFilter", "@Component")}},
        logging  => {[] of String, {"#{logging.delete('-')}/AuthFilter.java" => review_filter(logging.delete('-'), "AuthFilter", refusing: false), "#{logging.delete('-')}/FilterConfig.java" => registration.call(logging.delete('-'), "AuthFilter")}},
      })
      tags["GET /#{refusing.delete('-')}/admin/users"].should eq(["Protected by Servlet filter AuthFilter on /* (refuses with 401)"])
      tags["GET /#{logging.delete('-')}/admin/users"].should be_empty
    end

    beans = review_reactor({
      "lib"   => {[] of String, {"lib/TokenFilter.java" => review_filter("lib", "TokenFilter")}},
      "app-a" => {["lib"], {"appa/Cfg.java" => "package appa;\n@Configuration\npublic class Cfg {\n    @Bean\n    public TokenFilter tokenFilter() { return new TokenFilter(); }\n}\n"}},
      "app-b" => {["lib"], {} of String => String},
    })
    beans["GET /appa/admin/users"].should eq(["Protected by Servlet filter TokenFilter on /* (refuses with 401)"])
    beans["GET /appb/admin/users"].should be_empty

    scans = review_reactor({
      "app-a" => {[] of String, {"appa/Scan.java" => "package appa;\n@ServletComponentScan\n@Configuration\npublic class Scan {}\n"}},
      "app-b" => {[] of String, {"appb/KeyFilter.java" => review_filter("appb", "KeyFilter", "@WebFilter(\"/*\")")}},
    })
    scans.values.flatten.should be_empty

    components = review_reactor({
      "app-a" => {[] of String, {"appa/KeyFilter.java" => review_filter("appa", "KeyFilter", "@Component")}},
      "app-b" => {[] of String, {} of String => String},
    })
    components["GET /appa/admin/users"].size.should eq(1)
    components["GET /appb/admin/users"].should be_empty
  end
end

# Round two of the #3255 review: shapes where a caller without a credential
# still reaches the handler (lambdas, a refusal without `return`, murky
# credential locals, no-argument predicates), plus the context path.
REVIEW_FILTERS2 = {
  "j01_noarg_predicate_threadlocal" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    @Component
    public class KeyFilter extends OncePerRequestFilter {

        private boolean isPublic() {
            HttpServletRequest r = CURRENT.get();
            return r.getRequestURI().startsWith("/admin");
        }
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {

            if (isPublic()) {
                chain.doFilter(request, response);
                return;
            }
            if (request.getHeader("Authorization") == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "j02_isenabled_reads_header" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    @Component
    public class KeyFilter extends OncePerRequestFilter {

        private final ThreadLocal<HttpServletRequest> holder = new ThreadLocal<>();
        private boolean isEnabled() { return holder.get().getHeader("X-Skip") == null; }
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {

            holder.set(request);
            if (!isEnabled()) {
                chain.doFilter(request, response);
                return;
            }
            if (request.getHeader("Authorization") == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "j03_senderror_no_return" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    @Component
    public class KeyFilter extends OncePerRequestFilter {

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {

            if (request.getHeader("Authorization") == null) {
                response.sendError(401);
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "j04_optional_ifpresent" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    @Component
    public class KeyFilter extends OncePerRequestFilter {

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {

            Optional.ofNullable(request.getHeader("Authorization"))
                .filter(t -> !tokens.valid(t))
                .ifPresent(t -> response.setStatus(401));
            if (response.getStatus() == 401) return;
            chain.doFilter(request, response);
        }
    }
    JAVA
  "j06_refusal_after_chain" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    @Component
    public class KeyFilter extends OncePerRequestFilter {

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {

            String token = request.getHeader("Authorization");
            chain.doFilter(request, response);
            if (token == null) {
                response.setStatus(401);
            }
        }
    }
    JAVA
  "j07_early_return_no_chain" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    @Component
    public class KeyFilter extends OncePerRequestFilter {

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {

            String token = request.getHeader("Authorization");
            if (token != null && !valid(token)) {
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "j08_status_ternary" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    @Component
    public class KeyFilter extends OncePerRequestFilter {

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {

            String token = request.getHeader("Authorization");
            if (token != null && !valid(token)) {
                response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "j09_static_noarg_bypass" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    @Component
    public class KeyFilter extends OncePerRequestFilter {

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {

            if (SecurityBypass.isAnonymousAllowed()) {
                chain.doFilter(request, response);
                return;
            }
            if (request.getHeader("X-Api-Key") == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "j10_local_from_noarg" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    @Component
    public class KeyFilter extends OncePerRequestFilter {

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {

            String path = currentPath();
            if (path.startsWith("/admin")) {
                chain.doFilter(request, response);
                return;
            }
            if (request.getHeader("X-Api-Key") == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "j11_refusal_in_string" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    @Component
    public class KeyFilter extends OncePerRequestFilter {

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {

            String token = request.getHeader("Authorization");
            log.info("would sendError(401) for {}", token);
            chain.doFilter(request, response);
        }
    }
    JAVA
  "j12_default_credential" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    @Component
    public class KeyFilter extends OncePerRequestFilter {

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {

            String token = request.getHeader("Authorization");
            if (token == null) token = "guest";
            if (!tokens.contains(token)) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "j13_flag_or_missing" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    @Component
    public class KeyFilter extends OncePerRequestFilter {

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {

            String token = request.getHeader("Authorization");
            boolean ok = token == null || tokens.valid(token);
            if (!ok) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "j16_jwt_passthrough" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    @Component
    public class KeyFilter extends OncePerRequestFilter {

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {

            String header = request.getHeader("Authorization");
            if (header == null || !header.startsWith("Bearer ")) {
                chain.doFilter(request, response);
                return;
            }
            if (!jwt.valid(header.substring(7))) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  "k01_let_refusal" => {"src/main/kotlin/app/KeyFilter.kt", <<-KOTLIN},
    package app
    @Component
    class KeyFilter : OncePerRequestFilter() {

        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {

            request.getHeader("Authorization")?.let {
                if (!valid(it)) {
                    response.sendError(401)
                    return
                }
            }
            chain.doFilter(request, response)
        }
    }
    KOTLIN
  "k04_when_no_else" => {"src/main/kotlin/app/KeyFilter.kt", <<-KOTLIN},
    package app
    @Component
    class KeyFilter : OncePerRequestFilter() {

        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {

            val token = request.getHeader("Authorization")
            when {
                token != null && !valid(token) -> {
                    response.status = 401
                    return
                }
            }
            chain.doFilter(request, response)
        }
    }
    KOTLIN
  "k05_takeif_chain" => {"src/main/kotlin/app/KeyFilter.kt", <<-KOTLIN},
    package app
    @Component
    class KeyFilter : OncePerRequestFilter() {

        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {

            val ok = request.getHeader("Authorization")
                ?.takeIf { it.isNotBlank() }
                ?.let { valid(it) } ?: true
            if (!ok) {
                response.status = 401
                return
            }
            chain.doFilter(request, response)
        }
    }
    KOTLIN
  "k06_multiline_condition" => {"src/main/kotlin/app/KeyFilter.kt", <<-KOTLIN},
    package app
    @Component
    class KeyFilter : OncePerRequestFilter() {

        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {

            val token = request.getHeader("Authorization")
            if (request.method == "POST" &&
                token == null
            ) {
                response.status = 401
                return
            }
            chain.doFilter(request, response)
        }
    }
    KOTLIN
  "k08_noarg_isPublic" => {"src/main/kotlin/app/KeyFilter.kt", <<-KOTLIN},
    package app
    @Component
    class KeyFilter : OncePerRequestFilter() {

        private val isPublic: Boolean get() = RequestHolder.current().requestURI.startsWith("/admin")
        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {

            if (isPublic) return chain.doFilter(request, response)
            if (request.getHeader("Authorization") == null) {
                response.status = 401
                return
            }
            chain.doFilter(request, response)
        }
    }
    KOTLIN
  "k02_elvis_refusal" => {"src/main/kotlin/app/KeyFilter.kt", <<-KOTLIN},
    package app
    @Component
    class KeyFilter : OncePerRequestFilter() {

        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {

            val token = request.getHeader("Authorization") ?: run {
                response.sendError(401)
                return
            }
            chain.doFilter(request, response)
        }
    }
    KOTLIN
  "k03_return_at_label" => {"src/main/kotlin/app/KeyFilter.kt", <<-KOTLIN},
    package app
    @Component
    class KeyFilter : OncePerRequestFilter() {

        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {

            val token = request.getHeader("Authorization")
            if (token == null) {
                response.status = 401
                return@doFilterInternal
            }
            chain.doFilter(request, response)
        }
    }
    KOTLIN
  "k07_if_expression_noelse_brace" => {"src/main/kotlin/app/KeyFilter.kt", <<-KOTLIN},
    package app
    @Component
    class KeyFilter : OncePerRequestFilter() {

        override fun doFilterInternal(request: HttpServletRequest, response: HttpServletResponse, chain: FilterChain) {

            val token = request.getHeader("Authorization")
            if (token == null) response.sendError(401)
            else chain.doFilter(request, response)
        }
    }
    KOTLIN
  "cp1_properties" => {"src/main/java/app/KeyFilter.java", <<-JAVA},
    package app;
    public class KeyFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            if (request.getHeader("X-Api-Key") == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    @Configuration
    class FilterConfig {
        @Bean
        public FilterRegistrationBean<KeyFilter> reg() {
            FilterRegistrationBean<KeyFilter> r = new FilterRegistrationBean<>(new KeyFilter());
            r.addUrlPatterns("/admin/*");
            return r;
        }
    }
    JAVA
}

describe "SpringAuthTagger (servlet filter review cases, round two)" do
  it "emits no guard when a missing credential can reach chain.doFilter" do
    %w[j01_noarg_predicate_threadlocal j02_isenabled_reads_header j03_senderror_no_return j04_optional_ifpresent j06_refusal_after_chain j07_early_return_no_chain j08_status_ternary j09_static_noarg_bypass j10_local_from_noarg j11_refusal_in_string j12_default_credential j13_flag_or_missing j16_jwt_passthrough k01_let_refusal k04_when_no_else k05_takeif_chain k06_multiline_condition k08_noarg_isPublic].each do |name|
      review_case(name).each do |route, tags|
        {name, route, tags}.should eq({name, route, [] of String})
      end
    end
  end

  it "guards an elvis refusal, a labelled return and a refusal whose else hands on" do
    %w[k02_elvis_refusal k03_return_at_label k07_if_expression_noelse_brace].each do |name|
      review_case(name).values.should eq([["Protected by Servlet filter KeyFilter on /* (refuses with 401)"]] * 3)
    end
  end

  it "reads the context path from properties or YAML, and not from a profile or placeholder" do
    guarded = ["Protected by Servlet filter KeyFilter on /admin/* (refuses with 401)"]
    {
      "src/main/resources/application.properties" => "server.servlet.context-path=/admin\n",
      "src/main/resources/application.yml"        => "server:\n  servlet:\n    context-path: /admin\n",
      "src/main/resources/application.yaml"       => "server.servlet.context-path: /admin\n",
    }.each do |path, config|
      tags = review_case("cp1_properties", {path => config}, "/admin")
      tags["GET /admin/admin/users"].should eq(guarded)
      tags["GET /admin/items"].should be_empty
    end
    {
      "src/main/resources/application-prod.yml"   => "server:\n  servlet:\n    context-path: /admin\n",
      "src/main/resources/application.properties" => "server.servlet.context-path=${CTX:/admin}\n",
    }.each do |path, config|
      review_case("cp1_properties", {path => config}, "/admin").values.flatten.should be_empty
    end
  end

  it "maps a @Component of a library module only for the apps that scan its package" do
    tags = review_reactor({
      "lib"   => {[] of String, {"lib/TokenFilter.java" => review_filter("lib", "TokenFilter", "@Component")}},
      "app-a" => {["lib"], {"appa/Scan.java" => "package appa;\n@Configuration\n@ComponentScan(\"lib\")\npublic class Scan {}\n"}},
      "app-b" => {["lib"], {} of String => String},
    })
    tags["GET /appa/admin/users"].should eq(["Protected by Servlet filter TokenFilter on /* (refuses with 401)"])
    tags["GET /appb/admin/users"].should be_empty
  end
end
