require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

private def spring_tags(files : Hash(String, String), method : String, url : String, line : Int32? = nil) : Array(Tag)
  spring_endpoint(files, method, url, line).tags.select(&.tagger.==("spring_auth"))
end

# Writes `files` under a temp `src/main/java/com/example/`, tags one endpoint
# whose handler is `Controller.java` at `line` (nil: no handler), and
# returns it.
private def spring_endpoint(files : Hash(String, String), method : String, url : String, line : Int32? = nil) : Endpoint
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("spring_requires")
  dir = File.join(tmpdir, "src/main/java/com/example")
  Dir.mkdir_p(dir)
  files.each do |name, source|
    path = File.join(dir, name)
    File.write(path, source)
    CodeLocator.instance.register_path(path)
  end
  options = create_test_options
  options["base"] = YAML::Any.new(tmpdir)
  details = line ? Details.new(PathInfo.new(File.join(dir, "Controller.java"), line)) : Details.new
  details.technology = "java_spring"
  endpoint = SpringAuthTagger.new(options).perform([Endpoint.new(url, method, [] of Param, details)])[0]
  FileUtils.rm_rf(tmpdir)
  endpoint
end

private def atoms(tag : Tag) : Array(Array(String))
  (tag.requires || [] of Access::Clause).map(&.any_of.map(&.to_s))
end

private def chain(rules : String) : String
  <<-JAVA
    package com.example;

    @Configuration
    public class SecurityConfig {
        @Bean
        public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
            http.authorizeHttpRequests(auth -> auth
                #{rules}
            );
            return http.build();
        }
    }
    JAVA
end

# The handler sits on line 10.
private def controller(class_annotation : String, method_annotation : String) : String
  <<-JAVA
    package com.example;

    @RestController
    @RequestMapping("/api")
    #{class_annotation}
    public class Controller {

        #{method_annotation}
        @GetMapping("/items")
        public String items() {
            return "items";
        }
    }
    JAVA
end

describe "SpringAuthTagger access requirements" do
  it "reads a method-level annotation in place of the class-level one" do
    tags = spring_tags({"Controller.java" => controller("@PreAuthorize(\"hasRole('ADMIN')\")", "@PreAuthorize(\"hasRole('USER')\")")}, "GET", "/api/items", 10)
    tags.size.should eq(1)
    tags[0].description.should eq("Protected by Spring @PreAuthorize")
    atoms(tags[0]).should eq([["role:USER"]])
    clause = tags[0].requires.not_nil![0]
    {clause.source, File.basename(clause.path.not_nil!), clause.line}.should eq({"@PreAuthorize(\"hasRole('USER')\")", "Controller.java", 8})
  end

  it "reads the class-level annotation when the method has none" do
    tags = spring_tags({"Controller.java" => controller("@Secured(\"ROLE_ADMIN\")", "")}, "GET", "/api/items", 10)
    tags[0].description.should eq("Protected by Spring @Secured on the controller class")
    atoms(tags[0]).should eq([["role:ADMIN"]])
  end

  it "ANDs the matching chain rule onto the annotation, keeping the annotation's tag" do
    files = {
      "Controller.java"     => controller("", "@PreAuthorize(\"hasRole('ADMIN') or hasAuthority('posts:write')\")"),
      "SecurityConfig.java" => chain(%(.requestMatchers("/api/**").authenticated()\n.anyRequest().denyAll())),
    }
    tags = spring_tags(files, "GET", "/api/items", 10)
    tags.size.should eq(1)
    {tags[0].description, tags[0].path, tags[0].line}.should eq({"Protected by Spring @PreAuthorize", nil, nil})
    atoms(tags[0]).should eq([["role:ADMIN", "permission:posts:write"], ["authenticated"]])
    tags[0].requires.not_nil![1].source.should eq("authenticated()")
  end

  it "ANDs a chain denyAll onto the annotation" do
    files = {
      "Controller.java"     => controller("", "@Secured(\"ROLE_USER\")"),
      "SecurityConfig.java" => chain(%(.requestMatchers("/api/**").denyAll())),
    }
    tags = spring_tags(files, "GET", "/api/items", 10)
    tags.map(&.name).should eq(["auth", "denied"])
    atoms(tags[0]).should eq([["role:USER"], ["deny"]])
    tags[1].description.should eq(%(Denied by Spring Security denyAll via requestMatchers("/api/**")))
    atoms(tags[1]).should eq([["deny"]])
  end

  it "ANDs a registered interceptor onto a guarded route only where it matches" do
    interceptor = <<-JAVA
      package com.example;
      public class AuthInterceptor implements HandlerInterceptor {
          @Override
          public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
              if (request.getHeader("Authorization") == null) {
                  response.sendError(HttpServletResponse.SC_UNAUTHORIZED);
                  return false;
              }
              return true;
          }
      }
      JAVA
    web = <<-JAVA
      package com.example;
      @Configuration
      public class WebConfig implements WebMvcConfigurer {
          @Override
          public void addInterceptors(InterceptorRegistry registry) {
              registry.addInterceptor(new AuthInterceptor()).addPathPatterns("/api/**");
          }
      }
      JAVA
    files = {"Controller.java" => controller("", "@Secured(\"ROLE_USER\")"), "AuthInterceptor.java" => interceptor, "WebConfig.java" => web}
    tags = spring_tags(files, "GET", "/api/items", 10)
    tags.size.should eq(1)
    {tags[0].description, tags[0].path, tags[0].line}.should eq({"Protected by Spring @Secured", nil, nil})
    atoms(tags[0]).should eq([["role:USER"], ["unresolved"]])
    tags[0].requires.not_nil![1].source.should eq("Protected by Spring HandlerInterceptor AuthInterceptor")
    spring_endpoint(files, "GET", "/api/items", 10).resolution.should be_nil

    files["WebConfig.java"] = web.sub("/api/**", "/admin/**")
    atoms(spring_tags(files, "GET", "/api/items", 10)[0]).should eq([["role:USER"]])
  end

  it "ANDs a refusing servlet filter onto a chain rule's guard" do
    filter = <<-JAVA
      package com.example;
      @Component
      public class TokenFilter extends OncePerRequestFilter {
          @Override
          protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
              if (request.getHeader("Authorization") == null) {
                  response.sendError(HttpServletResponse.SC_UNAUTHORIZED);
                  return;
              }
              chain.doFilter(request, response);
          }
      }
      JAVA
    files = {"SecurityConfig.java" => chain(%(.requestMatchers("/admin/**").hasRole("ADMIN"))), "TokenFilter.java" => filter}
    tags = spring_tags(files, "GET", "/admin/users")
    tags.size.should eq(1)
    tags[0].description.should eq(%(Protected by Spring Security hasRole via requestMatchers("/admin/**")))
    atoms(tags[0]).should eq([["role:ADMIN"], ["unresolved"]])
    tags[0].requires.not_nil![1].source.should start_with("Protected by Servlet filter TokenFilter")
  end

  it "keeps the auth tag of an access(\"denyAll()\") rule and adds a denied tag" do
    tags = spring_tags({"SecurityConfig.java" => chain(%(.requestMatchers("/admin/**").access("denyAll()")))}, "GET", "/admin/users")
    tags.map { |tag| {tag.name, tag.description} }.should eq([
      {"auth", %(Protected by Spring Security access via requestMatchers("/admin/**")) + SpringAuthTagger::ACCESS_NOTE},
      {"denied", %(Denied by Spring Security access via requestMatchers("/admin/**"))},
    ])
    atoms(tags[1]).should eq([["deny"]])
  end

  it "tags a route an anyRequest denyAll decides as denied, not auth" do
    files = {"SecurityConfig.java" => chain(%(.requestMatchers("/api/**").authenticated()\n.anyRequest().denyAll()))}
    tags = spring_tags(files, "GET", "/other")
    tags.map { |tag| {tag.name, tag.description} }.should eq([{"denied", "Denied by Spring Security denyAll via anyRequest()"}])
    atoms(tags[0]).should eq([["deny"]])
  end

  it "tags a route a Kotlin anyExchange denyAll decides as denied, reading authorize's rule past its pattern" do
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
    closed = spring_tags({"WebFluxSecurityConfig.kt" => config}, "GET", "/closed")
    closed.map { |tag| {tag.name, tag.description} }.should eq([{"denied", "Denied by Spring Security denyAll via authorize(anyExchange)"}])
    atoms(closed[0]).should eq([["deny"]])
    guarded = spring_tags({"WebFluxSecurityConfig.kt" => config}, "GET", "/guarded/items")
    guarded.map(&.name).should eq(["auth"])
    atoms(guarded[0]).should eq([["role:USER"]])
  end

  it "adds nothing for a chain rule that permits all" do
    files = {
      "Controller.java"     => controller("", "@RolesAllowed(\"ADMIN\")"),
      "SecurityConfig.java" => chain(%(.requestMatchers("/api/**").permitAll())),
    }
    atoms(spring_tags(files, "GET", "/api/items", 10)[0]).should eq([["role:ADMIN"]])
  end

  it "keeps the chain rule's tag for an endpoint with no annotation, adding its requirement" do
    files = {"SecurityConfig.java" => chain(%(.requestMatchers("/admin/**").hasAnyRole("ADMIN", "OPS")))}
    tags = spring_tags(files, "GET", "/admin/users")
    tags.size.should eq(1)
    tags[0].description.should eq(%(Protected by Spring Security hasAnyRole via requestMatchers("/admin/**")))
    {File.basename(tags[0].path.not_nil!), tags[0].line}.should eq({"SecurityConfig.java", 8})
    atoms(tags[0]).should eq([["role:ADMIN", "role:OPS"]])
    tags[0].requires.not_nil![0].source.should eq(%(hasAnyRole("ADMIN", "OPS")))
  end

  it "reads an access() expression on a chain rule" do
    files = {"SecurityConfig.java" => chain(%(.requestMatchers("/admin/**").access("hasRole('ADMIN') and @audit.allowed(request)")))}
    atoms(spring_tags(files, "GET", "/admin/users")[0]).should eq([["role:ADMIN"], ["unresolved"]])
  end

  it "keeps a public annotation's requirement on the chain's tag" do
    files = {
      "Controller.java"     => controller("", "@PreAuthorize(\"isAnonymous()\")"),
      "SecurityConfig.java" => chain(%(.anyRequest().authenticated())),
    }
    tags = spring_tags(files, "GET", "/api/items", 10)
    tags.map(&.name).should eq(["auth", "anonymous"])
    tags[0].description.should eq("Protected by Spring Security authenticated via anyRequest()")
    atoms(tags[0]).should eq([["authenticated"], ["anonymous"]])
    tags[1].requires.should be_nil
  end
end

describe "SpringAuthTagger access requirements (unread and conditional chains)" do
  it "lets a setting lift a chain registered under @Profile" do
    config = chain(%(.anyRequest().authenticated())).sub("@Configuration", "@Configuration\n@Profile(\"auth\")")
    requires = spring_tags({"SecurityConfig.java" => config}, "GET", "/x")[0].requires.not_nil!
    requires.map(&.any_of.map(&.to_s)).should eq([["authenticated", "unresolved"]])
    requires[0].any_of[1].value.should eq(%(it is registered only under `@Profile("auth")`))
  end

  it "leaves a decision that holds for some verbs only unresolved" do
    rules = %(.requestMatchers(HttpMethod.GET, "/").permitAll()\n.requestMatchers(HttpMethod.DELETE, "/open/**").authenticated()\n.anyRequest().permitAll())
    open = spring_tags({"SecurityConfig.java" => chain(rules)}, "ANY", "/open/x")[0].requires.not_nil!
    open.map(&.any_of.map(&.value)).should eq([["for DELETE only"]])
    guarded = spring_tags({"SecurityConfig.java" => chain(rules.sub(".anyRequest().permitAll()", ".anyRequest().authenticated()"))}, "ANY", "/")[0].requires.not_nil!
    guarded.map(&.any_of.map(&.value)).should eq([["except for GET"]])
  end

  it "leaves a chain whose rules it does not read unresolved" do
    config = <<-JAVA
      package com.example;
      public class SecurityConfig {
          @Bean
          SecurityFilterChain chain(HttpSecurity http) throws Exception {
              http.authorizeHttpRequests(this::rules);
              return http.build();
          }
      }
      JAVA
    tag = spring_tags({"SecurityConfig.java" => config}, "GET", "/items")[0]
    tag.description.should eq("Protected by Spring Security, configured by the authorization rules of the chain in SecurityConfig.java, which noir does not read")
    tag.requires.not_nil!.map(&.any_of.map(&.to_s)).should eq([["unresolved"]])
    tag.requires.not_nil![0].any_of[0].value.should eq("authorizeHttpRequests")
  end
end
