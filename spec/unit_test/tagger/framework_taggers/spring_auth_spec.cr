require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "SpringAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/java/spring_auth"
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
      locator.push("file_map", file)
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
      locator.push("file_map", file)
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
      locator.push("file_map", file)
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
      locator.push("file_map", file)
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
      locator.push("file_map", file)
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
      locator.push("file_map", file)
    end

    endpoint = Endpoint.new("/api/other", "GET")

    tagger = SpringAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.any? { |tag| tag.name == "auth" && tag.description.includes?("anyRequest") }.should be_true
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
      CodeLocator.instance.push("file_map", config_path)

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
      CodeLocator.instance.push("file_map", config_path)

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
      CodeLocator.instance.push("file_map", config_path)

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
      CodeLocator.instance.push("file_map", config_path)

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
      CodeLocator.instance.push("file_map", config_path)

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
