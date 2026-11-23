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
def run_spring_multi_module(files : Hash(String, String), routes : Hash(String, String), scan : String = "") : Hash(String, Array(String))
  CodeLocator.instance.clear_all
  root = File.tempname("spring_multi_module")
  files.each do |relative, source|
    path = File.join(root, relative)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, source)
    CodeLocator.instance.register_path(path) if relative.starts_with?(scan)
  end
  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(File.join(root, scan))
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

  it "skips outbound @HttpExchange and @FeignClient declarations marked internal" do
    config = <<-JAVA
      public class SecurityConfig {
          @Bean
          SecurityFilterChain api(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(c -> c.anyRequest().hasRole("USER"));
              return http.build();
          }
      }
      JAVA
    CodeLocator.instance.clear_all
    root = File.tempname("spring_auth_internal")
    path = File.join(root, "SecurityConfig.java")
    Dir.mkdir_p(root)
    File.write(path, config)
    CodeLocator.instance.register_path(path)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(root)

    client_ep = Endpoint.new("/v1/users/{userId}", "GET", [Param.new("userId", "", "path")], Details.new(PathInfo.new(path, 1)))
    client_ep.internal = true
    endpoints = [client_ep]
    SpringAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(root)

    endpoints[0].tags.should be_empty
  end

  it "lets the permitAll list it cannot read lift the guard's requirement" do
    endpoints = run_spring_endpoints_map(files, {"GET /lib" => "lib/src/main/java/com/example/lib/Controller.java:2"})
    requires = endpoints["GET /lib"].tags[0].requires.not_nil!
    requires.map(&.any_of.map(&.to_s)).should eq([["authenticated", "unresolved"]])
    requires[0].any_of[1].value.should eq("the permitAll list bound from secure.ignored.urls")
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
    tags["GET /legacy/export"].should be_empty
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
                      .antMatchers("/guarded/**").authenticated()
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
      "GET /guarded/items",
      "GET /other",
    ])
    tags["GET /anon/hello"].should be_empty
    tags["GET /login-page"].should be_empty
    tags["POST /do-login"].should be_empty
    tags["GET /login-fail"].should be_empty
    tags["GET /guarded/items"].should eq(["Protected by Spring Security authenticated via antMatchers(\"/guarded/**\")"])
    tags["GET /other"].should be_empty

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
    endpoints[2].tags.map { |tag| {tag.name, tag.description} }.should eq([{"denied", "Denied by Spring Security denyAll via authorize(\"/legacy/**\")"}])
    endpoints[3].tags.map(&.description).should eq(["Protected by Spring Security authenticated via authorize(anyRequest)"])
  end

  it "keeps WebFlux anyExchange denyAll separate from an authenticated path rule" do
    config = <<-KOTLIN
      @Configuration
      class WebFluxSecurityConfig {
          @Bean
          fun chain(http: ServerHttpSecurity): SecurityWebFilterChain {
              return http.authorizeExchange {
                  authorize("/guarded/**", hasAuthority("ROLE_USER"))
                  authorize(anyExchange, denyAll)
              }.build()
          }
      }
      KOTLIN
    tags = run_spring_security_config({"WebFluxSecurityConfig.kt" => config}, ["GET /guarded/items", "GET /closed"])

    tags["GET /guarded/items"].should eq(["Protected by Spring Security hasAuthority via authorize(\"/guarded/**\")"])
    tags["GET /closed"].should be_empty
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

    endpoints[1].tags.map { |tag| {tag.name, tag.description, tag.line} }.should eq([{"denied", "Denied by Spring Security denyAll via requestMatchers(\"/legacy/**\")", 10}])
    endpoints[1].resolution.should be_nil
  end
end

# `framework` names the routes the analyzer marks framework-provided.
def run_spring_endpoints_map(files : Hash(String, String), routes : Hash(String, String), framework = [] of String) : Hash(String, Endpoint)
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
    endpoint = Endpoint.new(url, method, [] of Param, Details.new(PathInfo.new(File.join(root, file), line.to_i)))
    endpoint.add_tag(Analyzer::Java::JavaEngine::FRAMEWORK_PROVIDED_TAG) if framework.includes?(route)
    endpoint
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

  it "judges a static JSON or YAML file by the module serving it, not by every module" do
    interceptor = <<-JAVA
      package com.example.a;
      public class InterceptorA implements HandlerInterceptor {
          public boolean preHandle(HttpServletRequest req, HttpServletResponse res, Object h) throws Exception {
              res.sendError(401);
              return false;
          }
      }
      JAVA
    config = <<-JAVA
      package com.example.a;
      @Configuration
      public class ConfigA implements WebMvcConfigurer {
          public void addInterceptors(InterceptorRegistry registry) {
              registry.addInterceptor(new InterceptorA());
          }
      }
      JAVA
    files = {
      "pom.xml"                                                 => "<project><artifactId>root</artifactId></project>",
      "service-a/pom.xml"                                       => spring_module_pom("service-a", [] of String),
      "service-a/src/main/java/com/example/a/InterceptorA.java" => interceptor,
      "service-a/src/main/java/com/example/a/ConfigA.java"      => config,
      "service-a/src/main/resources/static/app.json"            => "{}",
      "service-b/pom.xml"                                       => spring_module_pom("service-b", [] of String),
      "service-b/src/main/resources/static/app.json"            => "{}",
      "service-b/src/main/resources/static/conf.yml"            => "a: 1",
    }
    CodeLocator.instance.clear_all
    root = File.tempname("spring_static_module")
    files.each do |relative, source|
      path = File.join(root, relative)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, source)
      CodeLocator.instance.register_path(path)
    end
    options = create_test_options
    options["base"] = YAML::Any.new(root)
    endpoints = ["service-a/src/main/resources/static/app.json", "service-b/src/main/resources/static/app.json", "service-b/src/main/resources/static/conf.yml"].map do |file|
      details = Details.new(PathInfo.new(File.join(root, file)))
      details.technology = "java_spring"
      Endpoint.new("/#{File.basename(file)}", "GET", [] of Param, details)
    end
    SpringAuthTagger.new(options).perform(endpoints)
    FileUtils.rm_rf(root)

    endpoints.map(&.tags.select(&.name.==("auth")).map(&.description)).should eq([
      ["Protected by Spring HandlerInterceptor InterceptorA"], [] of String, [] of String,
    ])
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

  it "reads a pass-through on a server-set request attribute as not taken by a caller without a credential" do
    review_case("m01_attribute_marked_pass")["GET /items"].should eq(["Protected by Servlet filter ConsumerFilter on /* (refuses with 401)"])
    review_case("m02_attribute_absent_pass").values.flatten.should be_empty
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
  # An earlier filter marks the request authenticated through server-side attributes.
  "m01_attribute_marked_pass" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;
    @Component
    public class ConsumerFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            if (Boolean.TRUE.equals(request.getAttribute("AUTHENTICATED"))) {
                chain.doFilter(request, response);
                return;
            }
            if (request.getAttribute("USER_TOKEN") != null) {
                chain.doFilter(request, response);
                return;
            }
            String token = request.getHeader("Authorization");
            if (token == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
  # The attribute test is true for a caller without it: the filter lets them through.
  "m02_attribute_absent_pass" => {"src/main/java/app/Filter.java", <<-JAVA},
    package app;
    @Component
    public class ConsumerFilter extends OncePerRequestFilter {
        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
            if (request.getAttribute("AUTHENTICATED") == null) {
                chain.doFilter(request, response);
                return;
            }
            String token = request.getHeader("Authorization");
            if (token == null) {
                response.sendError(401);
                return;
            }
            chain.doFilter(request, response);
        }
    }
    JAVA
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

  it "does not map a library filter the app's scan excludes" do
    {
      "@ComponentScan(basePackages = {\"appb\", \"lib\"}, excludeFilters = @ComponentScan.Filter(type = FilterType.ASSIGNABLE_TYPE, classes = TokenFilter.class))",
      "@ComponentScan(basePackages = {\"appb\", \"lib\"})\n@SpringBootApplication(exclude = TokenFilter.class)",
    }.each do |scan|
      tags = review_reactor({
        "lib"   => {[] of String, {"lib/TokenFilter.java" => review_filter("lib", "TokenFilter", "@Component")}},
        "app-a" => {["lib"], {"appa/Scan.java" => "package appa;\n@Configuration\n@ComponentScan(\"lib\")\npublic class Scan {}\n"}},
        "app-b" => {["lib"], {"appb/Scan.java" => "package appb;\n#{scan}\npublic class Scan {}\n"}},
      })
      tags["GET /appa/admin/users"].should eq(["Protected by Servlet filter TokenFilter on /* (refuses with 401)"])
      tags["GET /appb/admin/users"].should be_empty
    end
  end

  it "emits no guard when a library default stands in for a missing credential" do
    source = REVIEW_FILTERS2["j12_default_credential"][1]
      .sub("String token = request.getHeader(\"Authorization\");\n        if (token == null) token = \"guest\";",
        "String token = StringUtils.defaultIfBlank(request.getHeader(\"Authorization\"), \"guest\");")
    source.should contain("defaultIfBlank")
    review_case("j12_default_credential", {"src/main/java/app/KeyFilter.java" => source}).values.flatten.should be_empty
  end
end

def spring_chain_source(pkg : String, rule : String) : String
  <<-JAVA
    package #{pkg};

    public class SecurityConfig {
        @Bean
        SecurityFilterChain chain(HttpSecurity http) throws Exception {
            http.authorizeHttpRequests(c -> c.anyRequest().#{rule});
            return http.build();
        }
    }
    JAVA
end

SPRING_ITEMS_CONTROLLER = "public class Controller {\n    @GetMapping(\"/items\")\n    public String items() { return \"\"; }\n}\n"
SPRING_WEB_STARTER      = "dependencies {\n    implementation 'org.springframework.boot:spring-boot-starter-web'\n"

# A Gradle build where `admin` serves /items and `api` declares a hasRole
# chain; `admin_build` is admin's build file, `extra` more files.
def gradle_items_guard(admin_build : String, extra = {} of String => String) : Array(String)
  files = {
    "settings.gradle"                                           => "include 'api'\ninclude 'admin'\n",
    "api/build.gradle"                                          => "#{SPRING_WEB_STARTER}}\n",
    "api/src/main/java/com/example/api/SecurityConfig.java"     => spring_chain_source("com.example.api", "hasRole(\"USER\")"),
    "admin/build.gradle"                                        => admin_build,
    "admin/src/main/java/com/example/admin/ItemController.java" => SPRING_ITEMS_CONTROLLER,
  }
  run_spring_multi_module(files.merge(extra), {"GET /items" => "admin/src/main/java/com/example/admin/ItemController.java:2"})["GET /items"]
end

describe "SpringAuthTagger (Gradle build scoping)" do
  guarded = ["Protected by Spring Security hasRole via anyRequest()"]

  it "does not apply one Gradle app's chain to a sibling Gradle build" do
    tags = run_spring_multi_module({
      "admin-app/build.gradle.kts"                               => "dependencies {\n    implementation(\"org.springframework.boot:spring-boot-starter-security\")\n}\n",
      "admin-app/src/main/java/com/example/SecurityConfig.java"  => spring_chain_source("com.example", "hasRole(\"USER\")"),
      "admin-app/src/main/java/com/example/Controller.java"      => SPRING_ITEMS_CONTROLLER,
      "public-app/build.gradle.kts"                              => "dependencies { implementation(\"org.springframework.boot:spring-boot-starter-web\") }\n",
      "public-app/src/main/java/com/example/pub/Controller.java" => SPRING_ITEMS_CONTROLLER,
    }, {
      "GET /admin" => "admin-app/src/main/java/com/example/Controller.java:2",
      "GET /items" => "public-app/src/main/java/com/example/pub/Controller.java:2",
    })
    tags["GET /admin"].should eq(guarded)
    tags["GET /items"].should be_empty
  end

  it "does not apply a Maven app's chain to a Gradle app beside it" do
    tags = run_spring_multi_module({
      "admin-app/pom.xml"                                        => spring_module_pom("admin-app", ["spring-boot-starter-security"]),
      "admin-app/src/main/java/com/example/SecurityConfig.java"  => spring_chain_source("com.example", "hasRole(\"USER\")"),
      "public-app/build.gradle"                                  => "#{SPRING_WEB_STARTER}}\n",
      "public-app/src/main/java/com/example/pub/Controller.java" => SPRING_ITEMS_CONTROLLER,
    }, {"GET /items" => "public-app/src/main/java/com/example/pub/Controller.java:2"})
    tags["GET /items"].should be_empty
  end

  it "applies another module's chain only through a project dependency" do
    gradle_items_guard("#{SPRING_WEB_STARTER}}\n").should be_empty
    gradle_items_guard("#{SPRING_WEB_STARTER}    implementation project(':api')\n}\n").should eq(guarded)
    gradle_items_guard("#{SPRING_WEB_STARTER}    implementation(projects.api)\n}\n").should eq(guarded)
    gradle_items_guard("#{SPRING_WEB_STARTER}    testImplementation project(':api')\n}\n").should be_empty
  end

  it "decides a module with its own chain by that chain, not an unrelated module's" do
    own = {"admin/src/main/java/com/example/admin/SecurityConfig.java" => spring_chain_source("com.example.admin", "permitAll()")}
    gradle_items_guard("#{SPRING_WEB_STARTER}}\n", own).should be_empty
  end

  it "follows a project dependency through a transitive module in a relocated directory" do
    gradle_items_guard("#{SPRING_WEB_STARTER}    implementation project(':core')\n}\n", {
      "settings.gradle"        => "include 'api', 'admin', 'core'\nproject(':core').projectDir = file('libs/core')\n",
      "libs/core/build.gradle" => "dependencies { api project(':api') }\n",
    }).should eq(guarded)
  end

  it "keeps every chain of the build when something else can add a project dependency" do
    plain = "#{SPRING_WEB_STARTER}}\n"
    gradle_items_guard(plain, {"build.gradle" => "subprojects {\n    dependencies { implementation project(':api') }\n}\n"}).should eq(guarded)
    gradle_items_guard(plain, {"buildSrc/src/main/groovy/app.conventions.gradle" => "dependencies { implementation project(':api') }\n"}).should eq(guarded)
    gradle_items_guard("#{SPRING_WEB_STARTER}    implementation project(':unknown')\n}\n").should eq(guarded)
    gradle_items_guard("#{SPRING_WEB_STARTER}    implementation(project(mapOf(\"path\" to \":api\")))\n}\n").should eq(guarded)
    gradle_items_guard(plain, {"build.gradle.kts" => "subprojects {\n    dependencies { implementation(projects.api) }\n}\n"}).should eq(guarded)
  end

  it "keeps every chain when a project dependency's settings are not in the scan" do
    tags = run_spring_multi_module({
      "api/build.gradle"                                          => "#{SPRING_WEB_STARTER}}\n",
      "api/src/main/java/com/example/api/SecurityConfig.java"     => spring_chain_source("com.example.api", "hasRole(\"USER\")"),
      "admin/build.gradle"                                        => "#{SPRING_WEB_STARTER}    implementation project(':api')\n}\n",
      "admin/src/main/java/com/example/admin/ItemController.java" => SPRING_ITEMS_CONTROLLER,
    }, {"GET /items" => "admin/src/main/java/com/example/admin/ItemController.java:2"})
    tags["GET /items"].should eq(guarded)
  end

  it "follows a coordinate dependency on a module of another build" do
    tags = run_spring_multi_module({
      "security-lib/pom.xml"                                       => spring_module_pom("security-lib", ["spring-boot-starter-security"]),
      "security-lib/src/main/java/com/example/SecurityConfig.java" => spring_chain_source("com.example", "hasRole(\"USER\")"),
      "app/build.gradle"                                           => "#{SPRING_WEB_STARTER}    implementation 'com.example:security-lib:1.0'\n}\n",
      "app/src/main/java/com/example/app/Controller.java"          => SPRING_ITEMS_CONTROLLER,
    }, {"GET /items" => "app/src/main/java/com/example/app/Controller.java:2"})
    tags["GET /items"].should eq(guarded)
  end

  it "follows a coordinate dependency on an included build by its root project name" do
    tags = run_spring_multi_module({
      "shared/settings.gradle"                               => "rootProject.name = 'security-lib'\n",
      "shared/build.gradle"                                  => "#{SPRING_WEB_STARTER}}\n",
      "shared/src/main/java/com/example/SecurityConfig.java" => spring_chain_source("com.example", "hasRole(\"USER\")"),
      "app/settings.gradle"                                  => "includeBuild '../shared'\n",
      "app/build.gradle"                                     => "#{SPRING_WEB_STARTER}    implementation 'com.example:security-lib:1.0'\n}\n",
      "app/src/main/java/com/example/app/Controller.java"    => SPRING_ITEMS_CONTROLLER,
    }, {"GET /items" => "app/src/main/java/com/example/app/Controller.java:2"})
    tags["GET /items"].should eq(guarded)
  end
end

describe "SpringAuthTagger (configurations that must not read as open)" do
  guarded = ["Protected by Spring Security hasRole via anyRequest()"]
  boot_default = ["Protected by Spring Boot default security (Spring Security on the app's classpath, no SecurityFilterChain in it)"]
  boot_app = "@SpringBootApplication\npublic class App { public static void main(String[] a) { SpringApplication.run(App.class, a); } }\n"
  boot_app_files = ->(build_file : String, build : String) do
    {
      "app/#{build_file}"                                 => build,
      "app/src/main/java/com/example/App.java"            => boot_app,
      "app/src/main/java/com/example/Controller.java"     => SPRING_ITEMS_CONTROLLER,
      "other/build.gradle"                                => "#{SPRING_WEB_STARTER}}\n",
      "other/src/main/java/com/example/o/App.java"        => boot_app,
      "other/src/main/java/com/example/o/Controller.java" => SPRING_ITEMS_CONTROLLER,
    }
  end
  boot_default_of = ->(build_file : String, build : String) do
    run_spring_multi_module(boot_app_files.call(build_file, build), {"GET /items" => "app/src/main/java/com/example/Controller.java:2"})["GET /items"]
  end

  it "reads Spring Security on a Gradle Boot app's classpath, for Boot's default chain" do
    boot_default_of.call("build.gradle", "#{SPRING_WEB_STARTER}    implementation 'org.springframework.boot:spring-boot-starter-security'\n}\n").should eq(boot_default)
    boot_default_of.call("build.gradle.kts", "dependencies {\n    implementation(libs.spring.boot.starter.security)\n}\n").should eq(boot_default)
    # A BOM import, a version pin or the test kit puts nothing on the classpath.
    boot_default_of.call("build.gradle", "dependencyManagement { imports { mavenBom libs.org.springframework.security.spring.security.bom.get().toString() } }\n#{SPRING_WEB_STARTER}    testImplementation 'org.springframework.security:spring-security-test'\n}\n").should be_empty
    files = boot_app_files.call("build.gradle", "#{SPRING_WEB_STARTER}}\n").merge({"ci.gradle" => "configurations.all { resolutionStrategy { force \"org.springframework.security:spring-security-core:6.0\" } }\n"})
    run_spring_multi_module(files, {"GET /items" => "app/src/main/java/com/example/Controller.java:2"})["GET /items"].should be_empty
  end

  it "reads a WebFlux chain's pathMatchers and anyExchange rules" do
    config = <<-JAVA
      @EnableWebFluxSecurity
      public class SecurityConfig {
          @Bean
          SecurityWebFilterChain chain(ServerHttpSecurity http) {
              http.authorizeExchange(e -> e.pathMatchers("/public/**").permitAll().anyExchange().authenticated());
              return http.build();
          }
      }
      JAVA
    tags = run_spring_security_config({"SecurityConfig.java" => config}, ["GET /public/x", "GET /items"])
    tags["GET /public/x"].should be_empty
    tags["GET /items"].should eq(["Protected by Spring Security authenticated via anyExchange()"])
  end

  it "requires an authenticated caller under Boot's default chain" do
    files = boot_app_files.call("build.gradle", "#{SPRING_WEB_STARTER}    implementation 'org.springframework.boot:spring-boot-starter-security'\n}\n")
    tag = run_spring_endpoints_map(files, {"GET /items" => "app/src/main/java/com/example/Controller.java:2"})["GET /items"].tags[0]
    tag.requires.not_nil!.map { |clause| {clause.any_of.map(&.to_s), clause.source} }.should eq([{["authenticated"], boot_default[0]}])
  end

  it "leaves an XML <http> configuration it does not read unresolved" do
    xml = %(<beans:beans xmlns="http://www.springframework.org/schema/security" xmlns:beans="http://www.springframework.org/schema/beans">\n  <http>\n    <intercept-url pattern="/**" access="authenticated"/>\n  </http>\n</beans:beans>\n)
    endpoints = run_spring_endpoints_map({
      "app/pom.xml"                                   => spring_module_pom("app", ["spring-security-config"]),
      "app/src/main/webapp/WEB-INF/security.xml"      => xml,
      "app/src/main/java/com/example/Controller.java" => SPRING_ITEMS_CONTROLLER,
    }, {"GET /items" => "app/src/main/java/com/example/Controller.java:2"})
    endpoints["GET /items"].tags[0].requires.not_nil!.map(&.any_of.map(&.value)).should eq([["the XML <http> configuration"]])
  end

  it "guards an app whose security configuration it does not read" do
    xml = %(<beans:beans xmlns="http://www.springframework.org/schema/security" xmlns:beans="http://www.springframework.org/schema/beans">\n  <http>\n    <intercept-url pattern="/**" access="authenticated"/>\n  </http>\n</beans:beans>\n)
    tags = run_spring_multi_module({
      "app/pom.xml"                                     => spring_module_pom("app", ["spring-security-config"]),
      "app/src/main/webapp/WEB-INF/security.xml"        => xml,
      "app/src/main/java/com/example/Controller.java"   => SPRING_ITEMS_CONTROLLER,
      "other/pom.xml"                                   => spring_module_pom("other", [] of String),
      "other/src/main/java/com/example/Controller.java" => SPRING_ITEMS_CONTROLLER,
    }, {"GET /items" => "app/src/main/java/com/example/Controller.java:2", "GET /other" => "other/src/main/java/com/example/Controller.java:2"})
    tags["GET /items"].should eq(["Protected by Spring Security, configured by the XML <http> configuration, which noir does not read"])
    tags["GET /other"].should be_empty

    method_ref = <<-JAVA
      public class SecurityConfig {
          @Bean
          SecurityFilterChain chain(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(this::rules);
              return http.build();
          }
      }
      JAVA
    run_spring_security_config({"SecurityConfig.java" => method_ref}, ["GET /items"])["GET /items"].should eq(["Protected by Spring Security, configured by the authorization rules of the chain in SecurityConfig.java, which noir does not read"])
  end

  it "keeps a chain whose rules it cannot read inside its securityMatcher" do
    config = <<-JAVA
      public class SecurityConfig {
          @Bean
          SecurityFilterChain chain(HttpSecurity http) throws Exception {
              http.securityMatcher("/api/**").authorizeHttpRequests(this::rules);
              return http.build();
          }
      }
      JAVA
    tags = run_spring_security_config({"SecurityConfig.java" => config}, ["GET /api/x", "GET /public"])
    tags["GET /api/x"].size.should eq(1)
    tags["GET /public"].should be_empty
  end

  it "denies a request no authorizeHttpRequests or authorizeExchange rule matches, but not one of legacy authorizeRequests" do
    chain = ->(dsl : String) do
      <<-KOTLIN
        @EnableWebSecurity
        class SecurityConfig {
            @Bean
            fun chain(http: HttpSecurity): SecurityFilterChain {
                http {
                    #{dsl} {
                        authorize("/css/**", permitAll)
                        authorize("/user/**", hasAuthority("ROLE_USER"))
                    }
                }
                return http.build()
            }
        }
        KOTLIN
    end
    routes = ["GET /", "GET /css/a.css", "GET /user/1"]
    {"authorizeHttpRequests", "authorizeExchange"}.each do |dsl|
      tags = run_spring_security_config({"SecurityConfig.kt" => chain.call(dsl)}, routes)
      tags["GET /"].should be_empty
      tags["GET /css/a.css"].should be_empty
      tags["GET /user/1"].should eq(["Protected by Spring Security hasAuthority via authorize(\"/user/**\")"])
    end
    run_spring_security_config({"SecurityConfig.kt" => chain.call("authorizeRequests")}, routes)["GET /"].should be_empty
  end

  it "does not deny by default when a rule's matcher is one it cannot read" do
    chain = ->(endpoint_rule : String) do
      <<-JAVA
        public class SecurityConfig {
            @Bean
            SecurityFilterChain chain(HttpSecurity http) throws Exception {
                http.authorizeHttpRequests(a -> a.requestMatchers(EndpointRequest.toAnyEndpoint()).#{endpoint_rule}
                    .requestMatchers("/api/**").authenticated().requestMatchers("/pub").permitAll());
                return http.build();
            }
        }
        JAVA
    end
    routes = ["GET /actuator/health", "GET /api/x", "GET /pub"]
    {"permitAll()", "authenticated()"}.each do |endpoint_rule|
      tags = run_spring_security_config({"SecurityConfig.java" => chain.call(endpoint_rule)}, routes)
      tags["GET /actuator/health"].should be_empty
      tags["GET /api/x"].should eq(["Protected by Spring Security authenticated via requestMatchers(\"/api/**\")"])
      tags["GET /pub"].should be_empty
    end
  end

  it "does not let a security configuration outside any build unit or a commented switch reach an app" do
    xml = %(<beans:beans xmlns="http://www.springframework.org/schema/security"><http><intercept-url pattern="/**" access="authenticated"/></http></beans:beans>\n)
    tags = run_spring_multi_module({
      "docs/example-security.xml"                     => xml,
      "app/pom.xml"                                   => spring_module_pom("app", [] of String),
      "app/src/main/java/com/example/Controller.java" => SPRING_ITEMS_CONTROLLER,
      "app/src/main/java/com/example/S.java"          => "// @EnableWebSecurity was dropped\npublic class S {}\n",
    }, {"GET /items" => "app/src/main/java/com/example/Controller.java:2"})
    tags["GET /items"].should be_empty
  end

  it "reads an XML <http> that only permits as an open chain" do
    xml = %(<beans:beans xmlns="http://www.springframework.org/schema/security"><http pattern="/static/**" security="none"/><http><intercept-url pattern="/**" access="permitAll"/></http></beans:beans>\n)
    tags = run_spring_multi_module({
      "app/pom.xml"                                   => spring_module_pom("app", ["spring-boot-starter-security"]),
      "app/src/main/resources/security.xml"           => xml,
      "app/src/main/java/com/example/App.java"        => boot_app,
      "app/src/main/java/com/example/Controller.java" => SPRING_ITEMS_CONTROLLER,
    }, {"GET /items" => "app/src/main/java/com/example/Controller.java:2"})
    tags["GET /items"].should be_empty
  end

  it "takes Spring Security on a whole-build classpath only from the build, its logic or the module itself" do
    files = {
      "settings.gradle"                                 => "include 'admin', 'pub', 'lib'\n",
      "build.gradle"                                    => "project(':admin') { }\n",
      "admin/build.gradle"                              => "dependencies { implementation 'org.springframework.boot:spring-boot-starter-security' }\n",
      "admin/src/main/java/com/example/a/App.java"      => boot_app,
      "admin/src/main/java/com/example/a/C.java"        => "public class C {\n    @GetMapping(\"/admin\")\n    public String a() { return \"\"; }\n}\n",
      "pub/build.gradle"                                => "#{SPRING_WEB_STARTER}}\n",
      "pub/src/main/java/com/example/p/App.java"        => boot_app,
      "pub/src/main/java/com/example/p/Controller.java" => SPRING_ITEMS_CONTROLLER,
      "lib/build.gradle"                                => "dependencies { implementation 'org.springframework.security:spring-security-config' }\n",
      "lib/src/main/java/com/example/l/L.java"          => "@EnableWebSecurity\npublic class L {}\n",
    }
    tags = run_spring_multi_module(files, {"GET /admin" => "admin/src/main/java/com/example/a/C.java:2", "GET /items" => "pub/src/main/java/com/example/p/Controller.java:2"})
    tags["GET /admin"].size.should eq(1)
    tags["GET /items"].should be_empty
  end

  it "guards a non-Boot app that switches Spring Security on without a chain of its own" do
    tags = run_spring_multi_module({
      "app/build.gradle"                                  => "dependencies { implementation 'org.springframework.security:spring-security-web' }\n",
      "app/src/main/java/com/example/SecurityConfig.java" => "@EnableWebSecurity\npublic class SecurityConfig {}\n",
      "app/src/main/java/com/example/Controller.java"     => SPRING_ITEMS_CONTROLLER,
      "boot/build.gradle"                                 => "#{SPRING_WEB_STARTER}}\n",
      "boot/src/main/java/com/example/b/App.java"         => boot_app,
    }, {"GET /items" => "app/src/main/java/com/example/Controller.java:2"})
    tags["GET /items"].should eq(["Protected by Spring Security default chain (@EnableWebSecurity, no SecurityFilterChain on the app's classpath)"])
  end

  it "keeps every chain when a project dependency resolves only against an outer settings file" do
    gradle_items_guard("#{SPRING_WEB_STARTER}    implementation project(':api')\n}\n", {"admin/settings.gradle" => "rootProject.name = 'admin'\n"}).should eq(guarded)
  end

  it "does not follow a projectDir remap it cannot place" do
    gradle_items_guard("#{SPRING_WEB_STARTER}    implementation project(':api')\n}\n", {
      "settings.gradle" => "include 'api', 'admin'\nproject(':api').projectDir = file(\"$rootDir/libs/api\")\n",
    }).should eq(guarded)
  end

  it "keeps every chain when a binary convention plugin or a build outside the scan can add a dependency" do
    plugin = {"buildSrc/src/main/kotlin/AppConventions.kt" => "class AppConventions : Plugin<Project> {\n    override fun apply(target: Project) { target.dependencies.add(\"implementation\", target.project(\":api\")) }\n}\n"}
    gradle_items_guard("#{SPRING_WEB_STARTER}}\n", plugin).should eq(guarded)

    tags = run_spring_multi_module({
      "settings.gradle"                                                    => "include 'services:api', 'services:admin'\n",
      "build.gradle"                                                       => "subprojects { dependencies { implementation project(':services:api') } }\n",
      "services/api/build.gradle"                                          => "#{SPRING_WEB_STARTER}}\n",
      "services/api/src/main/java/com/example/api/SecurityConfig.java"     => spring_chain_source("com.example.api", "hasRole(\"USER\")"),
      "services/admin/build.gradle"                                        => "#{SPRING_WEB_STARTER}}\n",
      "services/admin/src/main/java/com/example/admin/ItemController.java" => SPRING_ITEMS_CONTROLLER,
    }, {"GET /items" => "services/admin/src/main/java/com/example/admin/ItemController.java:2"}, scan: "services")
    tags["GET /items"].should eq(guarded)
  end

  it "follows a Maven dependency on a Gradle module" do
    tags = run_spring_multi_module({
      "app/pom.xml"                                       => spring_module_pom("app", ["web", "spring-boot-starter-security"]),
      "app/src/main/java/com/example/SecurityConfig.java" => spring_chain_source("com.example", "hasRole(\"USER\")"),
      "app/src/main/java/com/example/App.java"            => boot_app,
      "web/build.gradle"                                  => "\n",
      "web/src/main/java/com/example/web/Controller.java" => SPRING_ITEMS_CONTROLLER,
    }, {"GET /items" => "web/src/main/java/com/example/web/Controller.java:2"})
    tags["GET /items"].should eq(guarded)
  end
end

describe "SpringAuthTagger guard resolution (#3567)" do
  it "follows readable method and class annotations, and marks unread expressions and composed names" do
    controller = <<-JAVA
      package com.example;
      @RestController
      @PreAuthorize("hasRole('ADMIN')")
      public class Controller {
          @GetMapping("/class")
          public String classGuard() { return "ok"; }
          @PreAuthorize("hasRole('USER')")
          @GetMapping("/method")
          public String methodGuard() { return "ok"; }
          @PreAuthorize("@permissions.check(authentication)")
          @GetMapping("/custom")
          public String customGuard() { return "ok"; }
          @PreAuthorize("denyAll()")
          @GetMapping("/deny-all")
          public String deniedForEveryCaller() { return "ok"; }
          @DenyAll
          @GetMapping("/deny-all-marker")
          public String deniedByMarker() { return "ok"; }
          @PostAuthorize("denyAll()")
          @GetMapping("/post-deny-all")
          public String deniedAfterRead() { return "ok"; }
          @AdminOnly
          @GetMapping("/composed")
          public String composedGuard() { return "ok"; }
      }
      JAVA
    denied_controller = <<-JAVA
      @DenyAll
      @RestController
      public class DeniedController {
          @GetMapping("/class-deny-all")
          public String deniedByClass() { return "ok"; }
      }
      JAVA
    meta = <<-JAVA
      package com.example;
      @PreAuthorize("@permissions.check(authentication)")
      public @interface AdminOnly {}
      JAVA
    kotlin = <<-KT
      @RestController
      class KotlinController {
          @PreAuthorize("hasRole('ADMIN')")
          @GetMapping("/kt-followed")
          fun followed() = "ok"
          @PreAuthorize("@permissions.check(authentication)")
          @GetMapping("/kt-custom")
          fun custom() = "ok"
      }
      KT
    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/Controller.java"       => controller,
      "src/main/java/com/example/DeniedController.java" => denied_controller,
      "src/main/java/com/example/AdminOnly.java"        => meta,
      "src/main/kotlin/com/example/KController.kt"      => kotlin,
    }, {
      "GET /class"           => "src/main/java/com/example/Controller.java:5",
      "GET /method"          => "src/main/java/com/example/Controller.java:8",
      "GET /custom"          => "src/main/java/com/example/Controller.java:11",
      "GET /deny-all"        => "src/main/java/com/example/Controller.java:14",
      "GET /deny-all-marker" => "src/main/java/com/example/Controller.java:17",
      "GET /post-deny-all"   => "src/main/java/com/example/Controller.java:20",
      "GET /composed"        => "src/main/java/com/example/Controller.java:23",
      "GET /class-deny-all"  => "src/main/java/com/example/DeniedController.java:4",
      "GET /kt-followed"     => "src/main/kotlin/com/example/KController.kt:4",
      "GET /kt-custom"       => "src/main/kotlin/com/example/KController.kt:7",
    })

    %w[GET\ /class GET\ /method GET\ /kt-followed].each do |route|
      endpoints[route].tags.map(&.name).should eq(["auth"])
      endpoints[route].resolution.should be_nil
    end
    %w[GET\ /custom GET\ /composed GET\ /kt-custom].each do |route|
      endpoints[route].tags.map(&.name).should eq(["auth"])
      endpoints[route].resolution.should eq({"guard" => Endpoint::RESOLUTION_HEURISTIC})
    end
    {
      "GET /deny-all"        => "Denied by Spring @PreAuthorize",
      "GET /deny-all-marker" => "Denied by Spring @DenyAll",
      "GET /post-deny-all"   => "Denied by Spring @PostAuthorize",
      "GET /class-deny-all"  => "Denied by Spring @DenyAll on the controller class",
    }.each do |route, description|
      endpoints[route].tags.map { |tag| {tag.name, tag.description} }.should eq([{"denied", description}])
      endpoints[route].tags[0].requires.not_nil!.map(&.any_of.map(&.to_s)).should eq([["deny"]])
      endpoints[route].resolution.should be_nil
    end
  end

  it "does not tag denyAll rules or their deny-by-default remainder as authentication" do
    config = <<-JAVA
      @Configuration
      public class SecurityConfig {
          @Bean
          SecurityFilterChain chain(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(auth -> auth
                  .requestMatchers("/closed/**").denyAll()
                  .requestMatchers("/roles/**").hasRole("ADMIN"));
              return http.build();
          }
      }
      JAVA
    controller = <<-JAVA
      @RestController
      public class Controller {
          @GetMapping("/closed/items") public String closed() { return "ok"; }
          @GetMapping("/roles/items") public String guarded() { return "ok"; }
          @GetMapping("/unmatched") public String unmatched() { return "ok"; }
      }
      JAVA
    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/SecurityConfig.java" => config,
      "src/main/java/com/example/Controller.java"     => controller,
    }, {
      "GET /closed/items" => "src/main/java/com/example/Controller.java:3",
      "GET /roles/items"  => "src/main/java/com/example/Controller.java:5",
      "GET /unmatched"    => "src/main/java/com/example/Controller.java:7",
    })

    {
      "GET /closed/items" => "Denied by Spring Security denyAll via requestMatchers(\"/closed/**\")",
      "GET /unmatched"    => "Denied by Spring Security: authorizeHttpRequests denies a request no rule matches",
    }.each do |route, description|
      endpoints[route].tags.map { |tag| {tag.name, tag.description} }.should eq([{"denied", description}])
      endpoints[route].tags[0].requires.not_nil!.map(&.any_of.map(&.to_s)).should eq([["deny"]])
      endpoints[route].resolution.should be_nil
    end
    endpoints["GET /roles/items"].tags.map(&.name).should eq(["auth"])
    endpoints["GET /roles/items"].resolution.should eq({"guard" => Endpoint::RESOLUTION_HEURISTIC})
  end

  it "follows literal role annotations on handlers" do
    controller = <<-JAVA
      @RestController
      public class Controller {
          @Secured("ROLE_ADMIN")
          @GetMapping("/secured")
          public String secured() { return "ok"; }
          @RolesAllowed("ADMIN")
          @GetMapping("/roles")
          public String roles() { return "ok"; }
          @PostAuthorize("hasRole('ADMIN')")
          @GetMapping("/post")
          public String post() { return "ok"; }
          @RequiresRoles("ADMIN")
          @GetMapping("/shiro-role")
          public String shiroRole() { return "ok"; }
      }
      JAVA
    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/Controller.java" => controller,
    }, {
      "GET /secured"    => "src/main/java/com/example/Controller.java:4",
      "GET /roles"      => "src/main/java/com/example/Controller.java:7",
      "GET /post"       => "src/main/java/com/example/Controller.java:10",
      "GET /shiro-role" => "src/main/java/com/example/Controller.java:13",
    })

    %w[GET\ /secured GET\ /roles GET\ /post GET\ /shiro-role].each do |route|
      endpoints[route].tags.map(&.name).should eq(["auth"])
      endpoints[route].resolution.should be_nil
    end
  end

  it "marks matched Shiro filter-chain rules as heuristic" do
    shiro = <<-JAVA
      class ShiroConfig {
          ShiroFilterFactoryBean factory() {
              ShiroFilterFactoryBean bean = new ShiroFilterFactoryBean();
              Map<String, String> chain = new LinkedHashMap<String, String>();
              chain.put("/shiro/**", "authc");
              bean.setFilterChainDefinitionMap(chain);
              return bean;
          }
      }
      JAVA
    controller = <<-JAVA
      @RestController
      public class Controller {
          @GetMapping("/shiro/admin")
          public String admin() { return "ok"; }
      }
      JAVA
    endpoint = run_spring_endpoints_map({
      "src/main/java/com/example/ShiroConfig.java" => shiro,
      "src/main/java/com/example/Controller.java"  => controller,
    }, {
      "GET /shiro/admin" => "src/main/java/com/example/Controller.java:3",
    })["GET /shiro/admin"]

    endpoint.tags.map(&.name).should eq(["auth"])
    endpoint.resolution.should eq({"guard" => Endpoint::RESOLUTION_HEURISTIC})
  end

  it "marks URL rule matches, while a followed annotation wins mixed evidence" do
    security = <<-JAVA
      @Configuration
      public class SecurityConfig {
          @Bean
          SecurityFilterChain chain(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(auth -> auth
                  .requestMatchers("/admin/**").hasRole("ADMIN")
                  .requestMatchers("/custom/**").access(new PermissionManager())
                  .requestMatchers("/public/**").permitAll()
                  .anyRequest().authenticated());
              return http.build();
          }
      }
      JAVA
    controller = <<-JAVA
      @RestController
      public class Controller {
          @GetMapping("/admin/users") public String admin() { return "ok"; }
          @GetMapping("/custom/items") public String custom() { return "ok"; }
          @GetMapping("/private") public String privateRoute() { return "ok"; }
          @GetMapping("/public/health") public String open() { return "ok"; }
          @PreAuthorize("hasRole('ADMIN')")
          @GetMapping("/mixed") public String mixed() { return "ok"; }
      }
      JAVA
    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/SecurityConfig.java" => security,
      "src/main/java/com/example/Controller.java"     => controller,
    }, {
      "GET /admin/users"   => "src/main/java/com/example/Controller.java:3",
      "GET /custom/items"  => "src/main/java/com/example/Controller.java:4",
      "GET /private"       => "src/main/java/com/example/Controller.java:5",
      "GET /public/health" => "src/main/java/com/example/Controller.java:6",
      "GET /mixed"         => "src/main/java/com/example/Controller.java:8",
    })

    %w[GET\ /admin/users GET\ /custom/items GET\ /private].each do |route|
      endpoints[route].tags.map(&.name).should eq(["auth"])
      endpoints[route].resolution.should eq({"guard" => Endpoint::RESOLUTION_HEURISTIC})
    end
    endpoints["GET /public/health"].tags.should be_empty
    endpoints["GET /public/health"].resolution.should be_nil
    endpoints["GET /mixed"].tags.map(&.name).should eq(["auth"])
    endpoints["GET /mixed"].resolution.should be_nil
  end

  it "marks the Spring Boot default chain and unread XML security configuration" do
    boot = run_spring_endpoints_map({
      "app/build.gradle"                              => "dependencies { implementation 'org.springframework.boot:spring-boot-starter-security' }\n",
      "app/src/main/java/com/example/App.java"        => "@SpringBootApplication\npublic class App {}\n",
      "app/src/main/java/com/example/Controller.java" => SPRING_ITEMS_CONTROLLER,
    }, {"GET /items" => "app/src/main/java/com/example/Controller.java:2"})["GET /items"]
    boot.tags.map(&.name).should eq(["auth"])
    boot.resolution.should eq({"guard" => Endpoint::RESOLUTION_HEURISTIC})

    xml = %(<beans:beans xmlns="http://www.springframework.org/schema/security" xmlns:beans="http://www.springframework.org/schema/beans"><http><intercept-url pattern="/**" access="authenticated"/></http></beans:beans>)
    unread = run_spring_endpoints_map({
      "app/pom.xml"                                   => spring_module_pom("app", ["spring-security-config"]),
      "app/src/main/webapp/WEB-INF/security.xml"      => xml,
      "app/src/main/java/com/example/Controller.java" => SPRING_ITEMS_CONTROLLER,
    }, {"GET /items" => "app/src/main/java/com/example/Controller.java:2"})["GET /items"]
    unread.tags.map(&.name).should eq(["auth"])
    unread.resolution.should eq({"guard" => Endpoint::RESOLUTION_HEURISTIC})
  end

  it "marks interceptor, servlet-filter and handler-shape matches" do
    interceptor = <<-JAVA
      public class AuthInterceptor implements HandlerInterceptor {
          public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
              if (request.getHeader("Authorization") == null) {
                  response.sendError(401);
                  return false;
              }
              return true;
          }
      }
      JAVA
    registration = <<-JAVA
      public class WebConfig implements WebMvcConfigurer {
          public void addInterceptors(InterceptorRegistry registry) {
              registry.addInterceptor(new AuthInterceptor()).addPathPatterns("/guarded/**");
          }
      }
      JAVA
    filter = <<-JAVA
      public class TokenFilter extends OncePerRequestFilter {
          protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) {
              if (request.getHeader("Authorization") == null) { response.setStatus(401); return; }
              chain.doFilter(request, response);
          }
      }
      @Configuration class FilterConfig {
          @Bean FilterRegistrationBean<TokenFilter> tokenFilter() {
              FilterRegistrationBean<TokenFilter> bean = new FilterRegistrationBean<>(new TokenFilter());
              bean.addUrlPatterns("/filtered/*");
              return bean;
          }
      }
      JAVA
    controller = <<-JAVA
      @RestController
      public class Controller {
          @GetMapping("/guarded/items") public String guarded() { return "ok"; }
          @GetMapping("/filtered/items") public String filtered() { return "ok"; }
          @GetMapping("/handler") public String handler(Principal principal) {
              if (principal == null) { return ResponseEntity.status(401).build(); }
              return "ok";
          }
      }
      JAVA
    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/AuthInterceptor.java" => interceptor,
      "src/main/java/com/example/WebConfig.java"       => registration,
      "src/main/java/com/example/TokenFilter.java"     => filter,
      "src/main/java/com/example/Controller.java"      => controller,
    }, {
      "GET /guarded/items"  => "src/main/java/com/example/Controller.java:3",
      "GET /filtered/items" => "src/main/java/com/example/Controller.java:4",
      "GET /handler"        => "src/main/java/com/example/Controller.java:5",
    })
    %w[GET\ /guarded/items GET\ /filtered/items GET\ /handler].each do |route|
      endpoints[route].tags.map(&.name).should eq(["auth"])
      endpoints[route].resolution.should eq({"guard" => Endpoint::RESOLUTION_HEURISTIC})
    end
  end

  it "merges guard into the existing claims" do
    root = File.tempname("spring_guard_resolution")
    Dir.mkdir_p(root)
    path = File.join(root, "Controller.java")
    File.write(path, "@PreAuthorize(\"@permissions.check(authentication)\")\n@GetMapping(\"/items\")\npublic String items() { return \"ok\"; }\n")
    CodeLocator.instance.clear_all
    CodeLocator.instance.register_path(path)
    options = create_test_options
    options["base"] = YAML::Any.new(root)
    endpoint = Endpoint.new("/items", "GET", [] of Param, Details.new(PathInfo.new(path, 2)))
    endpoint.resolution = {"prefix" => Endpoint::RESOLUTION_UNRESOLVED, "handler" => Endpoint::RESOLUTION_HEURISTIC}
    endpoints = [endpoint]
    SpringAuthTagger.new(options).perform(endpoints)
    FileUtils.rm_rf(root)
    endpoints.first.resolution.should eq({"prefix" => Endpoint::RESOLUTION_UNRESOLVED, "handler" => Endpoint::RESOLUTION_HEURISTIC, "guard" => Endpoint::RESOLUTION_HEURISTIC})
  end
end

describe "SpringAuthTagger (servlet path matchers)" do
  it "reads the servlet path of a matcher builder variable" do
    config = <<-JAVA
      public class WsSecurity {
          @Bean
          public SecurityFilterChain wsChain(HttpSecurity http, HandlerMappingIntrospector introspector) throws Exception {
              MvcRequestMatcher.Builder mvc = new MvcRequestMatcher.Builder(introspector).servletPath("/ws");
              http.securityMatcher(mvc.pattern("/**")).authorizeHttpRequests(c -> c.anyRequest().hasRole("USER"));
              return http.build();
          }
      }
      JAVA
    tags = run_spring_security_config({"WsSecurity.java" => config}, ["GET /items", "GET /ws/items"])
    tags["GET /items"].should be_empty
    tags["GET /ws/items"].should eq(["Protected by Spring Security hasRole via anyRequest()"])
  end

  it "scopes a chain matched by servletPath(...).pattern(...) to the servlet path" do
    config = <<-JAVA
      public class WsSecurity {
          @Bean
          public SecurityFilterChain wsChain(HttpSecurity http, HandlerMappingIntrospector introspector) throws Exception {
              MvcRequestMatcher.Builder mvc = new MvcRequestMatcher.Builder(introspector);
              http
                  .securityMatcher(mvc.servletPath("/ws").pattern("/**"))
                  .authorizeHttpRequests(c -> c.requestMatchers(mvc.servletPath("/ws").pattern("/open")).permitAll()
                      .anyRequest().hasRole("USER"));
              return http.build();
          }
      }
      JAVA
    tags = run_spring_security_config({"WsSecurity.java" => config}, ["GET /items", "GET /ws/items", "GET /ws/open"])
    tags["GET /items"].should be_empty
    tags["GET /ws/items"].should eq(["Protected by Spring Security hasRole via anyRequest()"])
    tags["GET /ws/open"].should be_empty
  end

  it "treats a chain whose servlet path it cannot read as scoped by an unreadable matcher" do
    config = <<-JAVA
      public class WsSecurity {
          @Bean
          public SecurityFilterChain wsChain(HttpSecurity http) throws Exception {
              http
                  .securityMatcher(mvc.servletPath(Paths.WS).pattern("/**"))
                  .authorizeHttpRequests(c -> c.anyRequest().hasRole("USER"));
              return http.build();
          }
      }
      JAVA
    run_spring_security_config({"WsSecurity.java" => config}, ["GET /items"])["GET /items"].should be_empty
  end
end

describe "SpringAuthTagger (profile-bound and test chains)" do
  chain = <<-JAVA
    @Configuration
    @Profile("auth")
    class Conf {
        @Bean
        SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
            return http.authorizeHttpRequests(a -> a.anyRequest().authenticated()).build();
        }
    }
    JAVA

  it "says a chain declared under @Profile guards only while the profile is active" do
    tags = run_spring_security_config({"Conf.java" => chain}, ["GET /x"])
    tags["GET /x"].size.should eq(1)
    tags["GET /x"][0].should contain("; a setting can lift it: it is registered only under `@Profile(\"auth\")`")
  end

  it "does not carry a sibling class's profile onto an unconditional chain" do
    plain = chain.sub("@Profile(\"auth\")", "").sub("class Conf", "class Other")
    tags = run_spring_security_config({"Conf.java" => plain + "\n" + chain}, ["GET /x"])
    tags["GET /x"].none?(&.includes?("a setting can lift it")).should be_true
  end

  it "says a module's guard comes from the assembly bundling it when the module alone has no chain" do
    boot = "@SpringBootApplication\npublic class App { }\n"
    files = {
      "pom.xml"                                             => "<project><artifactId>root</artifactId></project>",
      "admin/pom.xml"                                       => spring_module_pom("admin", ["spring-boot-starter-web"]),
      "admin/src/main/java/com/example/AdminApp.java"       => boot,
      "admin/src/main/java/com/example/Controller.java"     => "public class Controller {\n    @GetMapping(\"/x\")\n    public String x() { return \"x\"; }\n}\n",
      "portal/pom.xml"                                      => spring_module_pom("portal", ["spring-boot-starter-security"]),
      "portal/src/main/java/com/example/Conf.java"          => chain.sub("@Profile(\"auth\")", ""),
      "assembly/pom.xml"                                    => spring_module_pom("assembly", ["admin", "portal"]),
      "assembly/src/main/java/com/example/AssemblyApp.java" => boot,
    }
    tags = run_spring_multi_module(files, {"GET /x" => "admin/src/main/java/com/example/Controller.java:2"})
    tags["GET /x"].size.should eq(1)
    tags["GET /x"][0].should contain("admin run on its own has no such chain, only assembly, which bundles it")
  end

  configurers = <<-JAVA
    @Component
    class AuthorizationExchangeConfigurers {
        @Bean
        @Order(0)
        SecurityConfigurer api(RoleService roleService) {
            return http -> http.authorizeExchange(spec -> spec.pathMatchers("/api/**", "/apis/**")
                    .access(new RequestInfoAuthorizationManager(roleService)));
        }

        @Bean
        @Order(200)
        SecurityConfigurer pre() {
            return http -> http.authorizeExchange(spec -> spec.pathMatchers("/apis/public/**")
                    .permitAll()
                    .pathMatchers("/console/**").authenticated());
        }

        @Bean
        @Order
        SecurityConfigurer rest() {
            return http -> http.authorizeExchange(spec -> spec.anyExchange().permitAll());
        }
    }
    JAVA

  it "guards routes a SecurityConfigurer lambda sends to a custom authorization manager" do
    tags = run_spring_security_config({"Configurers.java" => configurers}, ["GET /apis/g/v1/posts", "GET /apis/public/x", "GET /console/home", "GET /other"])
    tags["GET /apis/g/v1/posts"].size.should eq(1)
    tags["GET /apis/g/v1/posts"][0].should contain("Protected by Spring Security access via pathMatchers(\"/apis/**\")")
    tags["GET /apis/g/v1/posts"][0].should contain("custom authorization manager decides")
    tags["GET /apis/public/x"].should be_empty
    tags["GET /console/home"].size.should eq(1)
    tags["GET /other"].should be_empty
  end

  it "reads an inline access() lambda by who it admits" do
    source = <<-JAVA
      @Component
      class Configurers {
          @Bean
          SecurityConfigurer a() {
              return http -> http.authorizeExchange(spec -> {
                  spec.pathMatchers(HttpMethod.GET, "/login", "/signup")
                      .access((authentication, context) -> authentication
                          .map(a -> !resolver.isAuthenticated(a))
                          .defaultIfEmpty(true)
                          .map(AuthorizationDecision::new));
                  spec.pathMatchers("/logout")
                      .access((authentication, context) -> authentication
                          .map(a -> !resolver.isAnonymous(a))
                          .map(AuthorizationDecision::new)
                          .switchIfEmpty(Mono.fromSupplier(() -> new AuthorizationDecision(false))));
                  spec.pathMatchers("/challenges/**")
                      .access((authentication, context) -> authentication
                          .map(TwoFactorAuthentication.class::isInstance)
                          .map(AuthorizationDecision::new)
                          .switchIfEmpty(Mono.fromSupplier(() -> new AuthorizationDecision(false))));
                  spec.pathMatchers("/deny1/**").access((auth, ctx) -> auth.filter(a -> !a.isAuthenticated()).map(a -> new AuthorizationDecision(false)));
                  spec.pathMatchers("/deny2/**").access((auth, ctx) -> auth.map(a -> new AuthorizationDecision(a.isAuthenticated() && !trust.isAuthenticated(other))));
                  spec.pathMatchers("/admin/**").access(new Manager());
                  spec.pathMatchers("/guest/**").access((authentication, context) -> authentication.map(a -> resolver.isAnonymous(a)).map(AuthorizationDecision::new));
              });
          }
      }
      JAVA
    tags = run_spring_security_config({"C.java" => source}, ["GET /login", "GET /signup", "GET /logout", "GET /challenges/totp", "GET /admin/x", "GET /guest/x", "GET /deny1/x", "GET /deny2/x"])
    tags["GET /login"].should be_empty
    tags["GET /signup"].should be_empty
    tags["GET /guest/x"].should be_empty
    tags["GET /logout"].size.should eq(1)
    tags["GET /logout"][0].should_not contain("custom authorization manager")
    tags["GET /challenges/totp"].size.should eq(1)
    tags["GET /admin/x"][0].should contain("custom authorization manager decides")
    tags["GET /deny1/x"].size.should eq(1)
    tags["GET /deny2/x"].size.should eq(1)
  end

  it "does not read a SecurityConfigurer declared in a test directory" do
    root = File.tempname("spring_test_configurer")
    path = File.join(root, "app/src/test/java/com/example/Configurers.java")
    Dir.mkdir_p(File.dirname(path))
    File.write(path, configurers)
    CodeLocator.instance.clear_all
    CodeLocator.instance.register_path(path)
    options = create_test_options
    options["base"] = YAML::Any.new(root)
    endpoint = Endpoint.new("/apis/g/v1/posts", "GET")
    SpringAuthTagger.new(options).perform([endpoint])
    FileUtils.rm_rf(root)
    endpoint.tags.select(&.name.==("auth")).should be_empty
  end

  it "ignores a SecurityFilterChain built by a test class" do
    root = File.tempname("spring_test_chain")
    path = File.join(root, "app/src/test/java/com/example/ScenarioTest.java")
    Dir.mkdir_p(File.dirname(path))
    File.write(path, chain.sub("class Conf", "class ScenarioTest").sub("@Profile(\"auth\")", ""))
    CodeLocator.instance.clear_all
    CodeLocator.instance.register_path(path)
    options = create_test_options
    options["base"] = YAML::Any.new(root)
    endpoint = Endpoint.new("/x", "GET")
    SpringAuthTagger.new(options).perform([endpoint])
    FileUtils.rm_rf(root)
    endpoint.tags.select(&.name.==("auth")).should be_empty
  end
end

describe "SpringAuthTagger (rules below the context path)" do
  build = "plugins { id 'org.springframework.boot' version '3.2.0'; id 'java' }\n"
  app = "@SpringBootApplication\npublic class App { public static void main(String[] a) { SpringApplication.run(App.class, a); } }\n"
  controller = "src/main/java/app/AdminController.java"
  auth_tags = ->(files : Hash(String, String), routes : Hash(String, String)) do
    run_spring_endpoints_map({"build.gradle" => build, "src/main/java/app/App.java" => app, controller => REVIEW_JAVA_CONTROLLER}.merge(files), routes)
      .transform_values { |endpoint| endpoint.tags.select(&.name.==("auth")).map(&.description) }
  end

  it "matches chain matchers against the URL below server.servlet.context-path" do
    chain = <<-JAVA
      @Configuration
      public class SecurityConfig {
          @Bean
          public SecurityFilterChain chain(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(auth -> auth
                  .requestMatchers("/items/**").permitAll()
                  .requestMatchers(HttpMethod.GET, "/admin/**").hasRole("ADMIN")
                  .anyRequest().authenticated());
              return http.build();
          }
      }
      JAVA
    tags = auth_tags.call({
      "src/main/java/app/SecurityConfig.java"     => chain,
      "src/main/resources/application.properties" => "server.servlet.context-path=/shop\n",
    }, {"GET /shop/admin/users" => "#{controller}:4", "POST /shop/admin/users" => "#{controller}:6", "GET /shop/items" => "#{controller}:8"})

    tags["GET /shop/items"].should be_empty
    tags["GET /shop/admin/users"].should eq(["Protected by Spring Security hasRole via requestMatchers(\"/admin/**\")"])
    tags["POST /shop/admin/users"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
  end

  it "matches Kotlin DSL rules against the URL below spring.webflux.base-path" do
    chain = <<-KOTLIN
      @Configuration
      @EnableWebFluxSecurity
      class SecurityConfig {
          @Bean
          fun chain(http: ServerHttpSecurity): SecurityWebFilterChain = http {
              authorizeExchange {
                  authorize("/items/**", permitAll)
                  authorize(anyExchange, authenticated)
              }
          }
      }
      KOTLIN
    tags = auth_tags.call({
      "src/main/kotlin/app/SecurityConfig.kt"     => chain,
      "src/main/resources/application.properties" => "spring.webflux.base-path=/blog\n",
    }, {"GET /blog/admin/users" => "#{controller}:4", "GET /blog/items" => "#{controller}:8"})

    tags["GET /blog/items"].should be_empty
    tags["GET /blog/admin/users"].should eq(["Protected by Spring Security authenticated via authorize(anyExchange)"])
  end

  it "matches interceptor path patterns against the URL below the context path" do
    interceptor = <<-JAVA
      public class AuthInterceptor implements HandlerInterceptor {
          @Override
          public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
              if (request.getHeader("Authorization") == null) {
                  response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Unauthorized");
                  return false;
              }
              return true;
          }
      }
      JAVA
    config = <<-JAVA
      @Configuration
      public class WebConfig implements WebMvcConfigurer {
          @Override
          public void addInterceptors(InterceptorRegistry registry) {
              registry.addInterceptor(new AuthInterceptor()).addPathPatterns("/admin/**");
          }
      }
      JAVA
    tags = auth_tags.call({
      "src/main/java/app/AuthInterceptor.java"    => interceptor,
      "src/main/java/app/WebConfig.java"          => config,
      "src/main/resources/application.properties" => "server.servlet.context-path=/shop\n",
    }, {"GET /shop/admin/users" => "#{controller}:4", "GET /shop/items" => "#{controller}:8"})

    tags["GET /shop/admin/users"].should eq(["Protected by Spring HandlerInterceptor AuthInterceptor"])
    tags["GET /shop/items"].should be_empty
  end

  it "matches chain matchers and interceptors below spring.mvc.servlet.path too" do
    chain = <<-JAVA
      @Configuration
      public class SecurityConfig {
          @Bean
          public SecurityFilterChain chain(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(auth -> auth
                  .requestMatchers("/items/**").permitAll()
                  .requestMatchers(HttpMethod.GET, "/admin/**").hasRole("ADMIN")
                  .anyRequest().authenticated());
              return http.build();
          }
      }
      JAVA
    yaml = "server:\n  servlet:\n    context-path: /shop\nspring:\n  mvc.servlet:\n    path: /app/\n"
    tags = auth_tags.call({
      "src/main/java/app/SecurityConfig.java" => chain,
      "src/main/resources/application.yml"    => yaml,
    }, {"GET /shop/app/admin/users" => "#{controller}:4", "GET /shop/app/items" => "#{controller}:8"})

    tags["GET /shop/app/items"].should be_empty
    tags["GET /shop/app/admin/users"].should eq(["Protected by Spring Security hasRole via requestMatchers(\"/admin/**\")"])

    interceptor = <<-JAVA
      public class AuthInterceptor implements HandlerInterceptor {
          @Override
          public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
              if (request.getHeader("Authorization") == null) {
                  response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Unauthorized");
                  return false;
              }
              return true;
          }
      }
      JAVA
    config = <<-JAVA
      @Configuration
      public class WebConfig implements WebMvcConfigurer {
          @Override
          public void addInterceptors(InterceptorRegistry registry) {
              registry.addInterceptor(new AuthInterceptor()).addPathPatterns("/admin/**");
          }
      }
      JAVA
    tags = auth_tags.call({
      "src/main/java/app/AuthInterceptor.java"    => interceptor,
      "src/main/java/app/WebConfig.java"          => config,
      "src/main/resources/application.properties" => "spring.mvc.servlet.path=/app\n",
    }, {"GET /app/admin/users" => "#{controller}:4", "GET /app/items" => "#{controller}:8"})

    tags["GET /app/admin/users"].should eq(["Protected by Spring HandlerInterceptor AuthInterceptor"])
    tags["GET /app/items"].should be_empty
  end
end

describe "SpringAuthTagger (Boot security auto-configuration excluded)" do
  controller = "public class ItemController {\n    @GetMapping(\"/items\")\n    public String items() { return \"\"; }\n}\n"
  base = {
    "demo/pom.xml"                                       => spring_module_pom("demo", ["spring-boot-starter-web", "spring-boot-starter-security"]),
    "demo/src/main/java/com/example/ItemController.java" => controller,
  }
  route = {"GET /items" => "demo/src/main/java/com/example/ItemController.java:2"}

  it "reports no Boot default chain when the app excludes SecurityAutoConfiguration" do
    app = "@SpringBootApplication(exclude = {SecurityAutoConfiguration.class, ManagementWebSecurityAutoConfiguration.class})\npublic class DemoApp {}\n"
    run_spring_multi_module(base.merge({"demo/src/main/java/com/example/DemoApp.java" => app}), route)["GET /items"].should be_empty

    kotlin = "@SpringBootApplication(excludeName = [\"org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration\"])\nclass DemoApp\n"
    run_spring_multi_module(base.merge({"demo/src/main/kotlin/com/example/DemoApp.kt" => kotlin}), route)["GET /items"].should be_empty

    property = "spring.autoconfigure.exclude=org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration\n"
    run_spring_multi_module(base.merge({
      "demo/src/main/java/com/example/DemoApp.java"    => "@SpringBootApplication\npublic class DemoApp {}\n",
      "demo/src/main/resources/application.properties" => property,
    }), route)["GET /items"].should be_empty
  end

  it "keeps the default chain when only another auto-configuration is excluded, or @EnableWebSecurity switches it on" do
    # A comment naming the auto-configuration excludes nothing.
    app = "// SecurityAutoConfiguration stays on\n@SpringBootApplication(exclude = {DataSourceAutoConfiguration.class, ManagementWebSecurityAutoConfiguration.class})\npublic class DemoApp {}\n"
    tags = run_spring_multi_module(base.merge({"demo/src/main/java/com/example/DemoApp.java" => app}), route)
    tags["GET /items"].size.should eq(1)
    tags["GET /items"][0].should start_with("Protected by Spring Boot default security")

    enabled = "@EnableWebSecurity\n@SpringBootApplication(exclude = SecurityAutoConfiguration.class)\npublic class DemoApp {}\n"
    tags = run_spring_multi_module(base.merge({"demo/src/main/java/com/example/DemoApp.java" => enabled}), route)
    tags["GET /items"].size.should eq(1)
    tags["GET /items"][0].should start_with("Protected by Spring Security default chain (@EnableWebSecurity")
  end

  it "keeps the default chain when the exclusion sits under @Profile" do
    app = "@SpringBootApplication\npublic class DemoApp {}\n"
    local = "@Profile(\"local\")\n@Configuration\n@EnableAutoConfiguration(exclude = SecurityAutoConfiguration.class)\npublic class LocalConfig {}\n"
    tags = run_spring_multi_module(base.merge({
      "demo/src/main/java/com/example/DemoApp.java"     => app,
      "demo/src/main/java/com/example/LocalConfig.java" => local,
    }), route)
    tags["GET /items"].size.should eq(1)
    tags["GET /items"][0].should start_with("Protected by Spring Boot default security")
  end
end

describe "SpringAuthTagger (concatenated matcher patterns)" do
  it "reads a securityMatcher and a requestMatchers pattern built by string concatenation" do
    config = <<-JAVA
      package com.example;

      public class SecurityConfig {
          private static final String INTERNAL = "/internal";

          @Bean
          @Order(1)
          SecurityFilterChain internal(HttpSecurity http) throws Exception {
              http.securityMatcher(Paths.INTERNAL + "/**")
                  .authorizeHttpRequests(a -> a
                      .requestMatchers(antMatcher(INTERNAL + "/admin" + "/**")).authenticated()
                      .anyRequest().permitAll());
              return http.build();
          }

          @Bean
          @Order(2)
          SecurityFilterChain api(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(a -> a.anyRequest().authenticated());
              return http.build();
          }
      }
      JAVA
    paths = "package com.example;\n\npublic class Paths {\n    public static final String INTERNAL = \"/internal\";\n}\n"
    tags = run_spring_security_config({"SecurityConfig.java" => config, "Paths.java" => paths},
      ["GET /internal/ping", "GET /internal/admin/jobs", "GET /items"])
    tags["GET /internal/ping"].should be_empty
    tags["GET /internal/admin/jobs"].should eq(["Protected by Spring Security authenticated via requestMatchers(\"/internal/admin/**\")"])
    tags["GET /items"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
  end
end

describe "SpringAuthTagger (WebSecurity ignoring)" do
  it "leaves paths that web.ignoring() takes out of every chain unguarded" do
    config = <<-JAVA
      package com.example;

      public class SecurityConfig {
          @Bean
          WebSecurityCustomizer ignored() {
              return web -> web.ignoring().requestMatchers(antMatcher("/login"), antMatcher("/static/**"));
          }

          @Bean
          SecurityFilterChain api(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(a -> a.anyRequest().authenticated());
              return http.build();
          }
      }
      JAVA
    tags = run_spring_security_config({"SecurityConfig.java" => config}, ["GET /login", "POST /login", "GET /static/app.js", "GET /items"])
    tags["GET /login"].should be_empty
    tags["POST /login"].should be_empty
    tags["GET /static/app.js"].should be_empty
    tags["GET /items"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
  end

  it "reads a WebSecurityCustomizer declared apart from the chain, per HTTP method" do
    customizer = <<-JAVA
      package com.example;

      @Configuration
      public class WebIgnoreConfig {
          @Bean
          public WebSecurityCustomizer webSecurityCustomizer() {
              return (web) -> web.ignoring().requestMatchers(HttpMethod.GET, "/docs/**");
          }
      }
      JAVA
    chain = <<-JAVA
      package com.example;

      public class SecurityConfig {
          @Bean
          SecurityFilterChain api(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(a -> a.anyRequest().authenticated());
              return http.build();
          }
      }
      JAVA
    tags = run_spring_security_config({"WebIgnoreConfig.java" => customizer, "SecurityConfig.java" => chain}, ["GET /docs/index.html", "POST /docs/upload"])
    tags["GET /docs/index.html"].should be_empty
    tags["POST /docs/upload"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
  end

  it "reads the legacy configure(WebSecurity) form" do
    config = <<-JAVA
      package com.example;

      public class LegacyConfig extends WebSecurityConfigurerAdapter {
          @Override
          public void configure(WebSecurity web) {
              web.ignoring().antMatchers("/error/**").antMatchers("/favicon.ico");
          }

          @Override
          protected void configure(HttpSecurity http) throws Exception {
              http.authorizeRequests().anyRequest().authenticated();
          }
      }
      JAVA
    tags = run_spring_security_config({"LegacyConfig.java" => config}, ["GET /error/404", "GET /favicon.ico", "GET /items"])
    tags["GET /error/404"].should be_empty
    tags["GET /favicon.ico"].should be_empty
    tags["GET /items"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
  end

  it "keeps the guards when the customizer is registered only under @Profile or @ConditionalOn" do
    chain = <<-JAVA
      package com.example;

      public class SecurityConfig {
          @Bean
          SecurityFilterChain api(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(a -> a.anyRequest().authenticated());
              return http.build();
          }
      }
      JAVA
    on_bean = <<-JAVA
      package com.example;

      @Configuration
      public class LocalConfig {
          @Profile("local")
          @Bean
          WebSecurityCustomizer openAll() {
              return web -> web.ignoring().requestMatchers("/**");
          }
      }
      JAVA
    on_class = <<-JAVA
      package com.example;

      @Configuration
      @ConditionalOnProperty(name = "demo.open", havingValue = "true")
      public class LocalConfig {
          @Bean
          WebSecurityCustomizer openAll() {
              return web -> {
                  web.ignoring().requestMatchers("/**");
              };
          }
      }
      JAVA
    [on_bean, on_class].each do |customizer|
      tags = run_spring_security_config({"LocalConfig.java" => customizer, "SecurityConfig.java" => chain}, ["GET /items"])
      tags["GET /items"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
    end
  end

  it "leaves a Shiro filter in charge of an ignored path" do
    config = <<-JAVA
      package com.example;

      public class SecurityConfig {
          @Bean
          WebSecurityCustomizer ignored() {
              return web -> web.ignoring().requestMatchers("/items/**");
          }

          @Bean
          ShiroFilterFactoryBean shiro() {
              ShiroFilterFactoryBean bean = new ShiroFilterFactoryBean();
              Map<String, String> chain = new LinkedHashMap<String, String>();
              chain.put("/items/**", "authc");
              bean.setFilterChainDefinitionMap(chain);
              return bean;
          }
      }
      JAVA
    tags = run_spring_security_config({"SecurityConfig.java" => config}, ["GET /items/1"])
    tags["GET /items/1"].size.should eq(1)
    tags["GET /items/1"][0].should start_with("Protected by Shiro authc")
  end
end

describe "SpringAuthTagger (Gradle scripts outside the build)" do
  it "does not read a CI init script under a dot directory as build logic" do
    plain = "#{SPRING_WEB_STARTER}}\n"
    gradle_items_guard(plain, {".github/ci/init.gradle" => "def core = gradle.rootProject.project(':api')\n"}).should be_empty
    gradle_items_guard(plain, {"gradle/shared.gradle" => "dependencies { implementation project(':api') }\n"}).should eq(["Protected by Spring Security hasRole via anyRequest()"])
  end
end

describe "SpringAuthTagger (Actuator routes)" do
  build = "dependencies {\n    implementation 'org.springframework.boot:spring-boot-starter-web'\n    implementation 'org.springframework.boot:spring-boot-starter-actuator'\n    implementation 'org.springframework.boot:spring-boot-starter-security'\n}\n"
  app = "@SpringBootApplication\npublic class App { public static void main(String[] a) { SpringApplication.run(App.class, a); } }\n"
  boot_default = ["Protected by Spring Boot default security (Spring Security on the app's classpath, no SecurityFilterChain in it)"]
  auth_of = ->(endpoints : Hash(String, Endpoint), route : String) { endpoints[route].tags.select(&.name.==("auth")).map(&.description) }

  it "leaves the Actuator health endpoint public under Boot's default security" do
    endpoints = run_spring_endpoints_map({
      "build.gradle"                              => build,
      "src/main/java/com/example/App.java"        => app,
      "src/main/java/com/example/Controller.java" => "public class Controller {\n    @GetMapping(\"/health\")\n    public String health() { return \"\"; }\n}\n",
    }, {
      "GET /manage/health" => "build.gradle:3",
      "GET /manage/info"   => "build.gradle:3",
      "GET /health"        => "src/main/java/com/example/Controller.java:2",
    }, ["GET /manage/health", "GET /manage/info"])
    auth_of.call(endpoints, "GET /manage/health").should be_empty
    auth_of.call(endpoints, "GET /manage/info").should eq(boot_default)
    # The app's own /health is not the Actuator's.
    auth_of.call(endpoints, "GET /health").should eq(boot_default)

    # The same holds when @EnableWebSecurity sits on a class with no chain.
    endpoints = run_spring_endpoints_map({
      "build.gradle"                            => build,
      "src/main/java/com/example/App.java"      => app,
      "src/main/java/com/example/Security.java" => "@Configuration\n@EnableWebSecurity\npublic class Security {}\n",
    }, {"GET /manage/health" => "build.gradle:3", "GET /manage/info" => "build.gradle:3"}, ["GET /manage/health", "GET /manage/info"])
    auth_of.call(endpoints, "GET /manage/health").should be_empty
    auth_of.call(endpoints, "GET /manage/info").should eq(["Protected by Spring Security default chain (@EnableWebSecurity, no SecurityFilterChain on the app's classpath)"])
  end

  it "decides Actuator routes on the management port by the chain matching that port" do
    config = <<-JAVA
      @Configuration
      public class OpsSecurityConfig {
          @Autowired ManagementServerProperties ops;

          @Bean
          @Order(0)
          SecurityFilterChain opsChain(HttpSecurity http) throws Exception {
              http.securityMatcher(request -> ops.getPort().equals(request.getLocalPort()))
                  .authorizeHttpRequests(c -> c.anyRequest().permitAll());
              return http.build();
          }

          @Bean
          @Order(1)
          SecurityFilterChain appChain(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(c -> c.anyRequest().authenticated());
              return http.build();
          }
      }
      JAVA
    files = {
      "build.gradle"                                     => build,
      "src/main/java/com/example/App.java"               => app,
      "src/main/java/com/example/OpsSecurityConfig.java" => config,
      "src/main/java/com/example/Controller.java"        => SPRING_ITEMS_CONTROLLER,
    }
    routes = {"GET /manage/health" => "build.gradle:3", "GET /items" => "src/main/java/com/example/Controller.java:2"}
    authenticated = ["Protected by Spring Security authenticated via anyRequest()"]

    endpoints = run_spring_endpoints_map(files.merge({"src/main/resources/application.properties" => "management.server.port=${OPS_PORT:9091}\n"}), routes, ["GET /manage/health"])
    auth_of.call(endpoints, "GET /manage/health").should be_empty
    auth_of.call(endpoints, "GET /items").should eq(authenticated)
    # An imported configuration does not move the port the app sets.
    imported = {"src/main/resources/application.yml" => "management:\n  server.port: 9091\nspring:\n  config.import: optional:file:./extra.yml\n"}
    auth_of.call(run_spring_endpoints_map(files.merge(imported), routes, ["GET /manage/health"]), "GET /manage/health").should be_empty

    # Without its own port the Actuator answers on the app's port.
    endpoints = run_spring_endpoints_map(files, routes, ["GET /manage/health"])
    auth_of.call(endpoints, "GET /manage/health").should eq(authenticated)

    # An app with no configuration of its own runs on the one a module on
    # its classpath ships.
    bundled = {
      "settings.gradle"                                       => "include 'core', 'bundle'\n",
      "core/build.gradle"                                     => build,
      "core/src/main/java/com/example/OpsSecurityConfig.java" => config,
      "core/src/main/resources/application.properties"        => "management.server.port=9091\n",
      "bundle/build.gradle"                                   => build.sub("dependencies {\n", "dependencies {\n    implementation project(':core')\n"),
      "bundle/src/main/java/com/example/b/App.java"           => app,
    }
    endpoints = run_spring_endpoints_map(bundled, {"GET /manage/health" => "bundle/build.gradle:4"}, ["GET /manage/health"])
    auth_of.call(endpoints, "GET /manage/health").should be_empty

    # A path-scoped chain ordered before the port chain sees the request first.
    first = config.sub("@Order(0)\n", "@Order(5)\n").sub(
      "    @Bean\n    @Order(1)",
      "    @Bean\n    @Order(0)\n    SecurityFilterChain manageChain(HttpSecurity http) throws Exception {\n        http.securityMatcher(\"/manage/**\")\n            .authorizeHttpRequests(c -> c.anyRequest().authenticated());\n        return http.build();\n    }\n\n    @Bean\n    @Order(1)")
    endpoints = run_spring_endpoints_map(files.merge({"src/main/java/com/example/OpsSecurityConfig.java" => first, "src/main/resources/application.properties" => "management.server.port=9091\n"}), routes, ["GET /manage/health"])
    auth_of.call(endpoints, "GET /manage/health").should eq(authenticated)
  end
end

describe "SpringAuthTagger (HandlerInterceptor path constants)" do
  interceptor = <<-JAVA
    package com.example;

    public class KeyInterceptor implements HandlerInterceptor {
        @Override
        public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
            if (request.getHeader("X-Key") == null) {
                response.sendError(HttpServletResponse.SC_UNAUTHORIZED);
                return false;
            }
            return true;
        }
    }
    JAVA
  controller = "public class Controller {\n    @GetMapping(\"/items/{id}\")\n    public String item() { return \"\"; }\n}\n"
  routes = {
    "GET /items/1"      => "src/main/java/com/example/Controller.java:2",
    "GET /items/open/1" => "src/main/java/com/example/Controller.java:2",
    "GET /home"         => "src/main/java/com/example/Controller.java:2",
  }
  guarded_routes = ->(registration : String) do
    config = <<-JAVA
      package com.example;

      @Configuration
      public class WebConfig implements WebMvcConfigurer {
          private static final String BASE = "/items";
          private static final String ITEM_PATHS = "/items/**";
          private static final String OPEN_PATHS = "/items/open/**";
          private static final List<String> ITEM_LIST = List.of("/items/**");

          @Override
          public void addInterceptors(InterceptorRegistry registry) {
              registry.addInterceptor(new KeyInterceptor())#{registration};
          }
      }
      JAVA
    endpoints = run_spring_endpoints_map({
      "src/main/java/com/example/KeyInterceptor.java" => interceptor,
      "src/main/java/com/example/WebConfig.java"      => config,
      "src/main/java/com/example/Controller.java"     => controller,
    }, routes)
    routes.keys.select { |route| endpoints[route].tags.any?(&.name.==("auth")) }
  end

  it "reads String constants and concatenations as path patterns" do
    guarded_routes.call(".addPathPatterns(ITEM_PATHS).excludePathPatterns(OPEN_PATHS)").should eq(["GET /items/1"])
    guarded_routes.call(".addPathPatterns(BASE + \"/**\").excludePathPatterns(OPEN_PATHS)").should eq(["GET /items/1"])
    guarded_routes.call(".addPathPatterns(List.of(\"/items/**\"))").should eq(["GET /items/1", "GET /items/open/1"])
  end

  it "reads collections of constants and List fields" do
    guarded_routes.call(".addPathPatterns(List.of(ITEM_PATHS))").should eq(["GET /items/1", "GET /items/open/1"])
    guarded_routes.call(".addPathPatterns(ITEM_LIST).excludePathPatterns(OPEN_PATHS)").should eq(["GET /items/1"])
  end

  it "keeps the include patterns it reads beside one it cannot" do
    guarded_routes.call(".addPathPatterns(\"/items/**\", patterns())").should eq(["GET /items/1", "GET /items/open/1"])
    guarded_routes.call(".addPathPatterns(Arrays.asList(\"/items/**\", patterns()))").should eq(["GET /items/1", "GET /items/open/1"])
  end

  it "does not widen an include pattern it cannot read to every route" do
    guarded_routes.call(".addPathPatterns(patterns())").should be_empty
  end
end

# Auth tags of GET /api/items and GET /public/ping when `interceptor` is
# registered by `registration` inside `addInterceptors` on `/api/**`.
private def kotlin_interceptor_guards(interceptor : String, registration : String, members = "", extra = {} of String => String) : Array(Array(String))
  config = <<-KT
    package com.example

    @Configuration
    class WebConfig : WebMvcConfigurer {
    #{members}
        override fun addInterceptors(registry: InterceptorRegistry) {
            #{registration}.addPathPatterns("/api/**")
        }
    }
    KT
  controller = <<-KT
    package com.example

    @RestController
    class ItemController {
        @GetMapping("/api/items")
        fun list(): String = "a"

        @GetMapping("/public/ping")
        fun ping(): String = "p"
    }
    KT
  endpoints = run_spring_endpoints_map({
    "src/main/kotlin/com/example/ApiKeyInterceptor.kt" => "package com.example\n\n#{interceptor}",
    "src/main/kotlin/com/example/WebConfig.kt"         => config,
    "src/main/kotlin/com/example/ItemController.kt"    => controller,
  }.merge(extra), {
    "GET /api/items"   => "src/main/kotlin/com/example/ItemController.kt:5",
    "GET /public/ping" => "src/main/kotlin/com/example/ItemController.kt:8",
  })
  endpoints.values.map { |endpoint| endpoint.tags.select(&.name.==("auth")).map(&.description) }
end

KOTLIN_SEND_ERROR_PRE_HANDLE = <<-KT
      override fun preHandle(request: HttpServletRequest, response: HttpServletResponse, handler: Any): Boolean {
          if (request.getHeader("X-Api-Key") != "k") {
              response.sendError(HttpServletResponse.SC_UNAUTHORIZED)
              return false
          }
          return true
      }
  }
  KT

describe "SpringAuthTagger (Kotlin HandlerInterceptor shapes)" do
  it "reads a Kotlin throw of an auth exception, which has no `new`, as a refusal" do
    interceptor = <<-KT
      class ApiKeyInterceptor : HandlerInterceptor {
          override fun preHandle(request: HttpServletRequest, response: HttpServletResponse, handler: Any): Boolean {
              if (request.getHeader("X-Api-Key") != "k") {
                  throw UnauthorizedException("missing key")
              }
              return true
          }
      }
      KT
    kotlin_interceptor_guards(interceptor, "registry.addInterceptor(ApiKeyInterceptor())").should eq([
      ["Protected by Spring HandlerInterceptor ApiKeyInterceptor"], [] of String,
    ])
  end

  it "does not read a Kotlin throw of a non-auth exception as a refusal" do
    interceptor = <<-KT
      class ApiKeyInterceptor : HandlerInterceptor {
          override fun preHandle(request: HttpServletRequest, response: HttpServletResponse, handler: Any): Boolean {
              if (request.getHeader("X-Trace") == null) {
                  throw IllegalStateException("no trace")
              }
              return true
          }
      }
      KT
    kotlin_interceptor_guards(interceptor, "registry.addInterceptor(ApiKeyInterceptor())").should eq([[] of String, [] of String])
  end

  it "reads an AsyncHandlerInterceptor and a class header whose constructor spans many lines" do
    async = "class ApiKeyInterceptor : AsyncHandlerInterceptor {\n" + KOTLIN_SEND_ERROR_PRE_HANDLE
    long_header = <<-KT
      @Component
      class ApiKeyInterceptor(
          private val first: String,
          private val second: String,
          private val third: String,
      ) : HandlerInterceptor {

      KT
    [async, long_header + KOTLIN_SEND_ERROR_PRE_HANDLE].each do |interceptor|
      kotlin_interceptor_guards(interceptor, "registry.addInterceptor(ApiKeyInterceptor())").should eq([
        ["Protected by Spring HandlerInterceptor ApiKeyInterceptor"], [] of String,
      ])
    end
  end

  it "resolves an interceptor registered through a Kotlin @Bean factory function" do
    members = <<-KT
        @Bean
        fun apiKeyInterceptor(): ApiKeyInterceptor {
            return ApiKeyInterceptor()
        }
      KT
    interceptor = "class ApiKeyInterceptor : HandlerInterceptor {\n" + KOTLIN_SEND_ERROR_PRE_HANDLE
    kotlin_interceptor_guards(interceptor, "registry.addInterceptor(apiKeyInterceptor())", members).should eq([
      ["Protected by Spring HandlerInterceptor ApiKeyInterceptor"], [] of String,
    ])
  end

  it "reads the type a factory declared as the HandlerInterceptor interface constructs" do
    interceptor = "class ApiKeyInterceptor : HandlerInterceptor {\n" + KOTLIN_SEND_ERROR_PRE_HANDLE
    {
      "  @Bean\n  fun apiKeyInterceptor(): HandlerInterceptor = ApiKeyInterceptor()\n",
      "  @Bean\n  fun apiKeyInterceptor(): HandlerInterceptor {\n      return ApiKeyInterceptor()\n  }\n",
    }.each do |members|
      kotlin_interceptor_guards(interceptor, "registry.addInterceptor(apiKeyInterceptor())", members).should eq([
        ["Protected by Spring HandlerInterceptor ApiKeyInterceptor"], [] of String,
      ])
    end
  end

  it "does not take a bodiless class for the interceptor an object below it declares" do
    interceptor = <<-KT
      data class ApiKeyInterceptor(val header: String)

      val ENABLED = true

      fun guard(): HandlerInterceptor {
          return object : HandlerInterceptor {
              override fun preHandle(request: HttpServletRequest, response: HttpServletResponse, handler: Any): Boolean {
                  if (request.getHeader("X-Api-Key") != "k") {
                      response.sendError(401)
                      return false
                  }
                  return true
              }
          }
      }
      KT
    kotlin_interceptor_guards(interceptor, "registry.addInterceptor(ApiKeyInterceptor())").should eq([[] of String, [] of String])
  end

  it "keeps reading interceptors past a class with no body before a long file" do
    filler = "package com.example\n\nclass Holder\n" + (1..12_000).map { |i| "val v#{i} = #{i} + 1\n" }.join + "val type = \"HandlerInterceptor\"\n"
    interceptor = "class ApiKeyInterceptor : HandlerInterceptor {\n" + KOTLIN_SEND_ERROR_PRE_HANDLE
    kotlin_interceptor_guards(interceptor, "registry.addInterceptor(ApiKeyInterceptor())", extra: {"src/main/kotlin/com/example/Util.kt" => filler}).should eq([
      ["Protected by Spring HandlerInterceptor ApiKeyInterceptor"], [] of String,
    ])
  end
end
