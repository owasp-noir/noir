require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Write `files` (relative path => source) under a temp root and run
# SpringAuthTagger over `routes` ("METHOD /url" => "relative/File.java:line").
def run_spring_markers(files : Hash(String, String), routes : Hash(String, String)) : Hash(String, Array(String))
  CodeLocator.instance.clear_all
  root = File.tempname("spring_markers")
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

MARKER_DIR  = "src/main/java/com/example/"
ANY_REQUEST = "Protected by Spring Security authenticated via anyRequest()"

# The utility class a permitAll matcher is fed from: `urls` walks the
# handler mappings and reads `reader`; `extra` adds a method of its own.
def marker_utils(reader : String, extra : String = "", cond : String? = nil, add : String = "out.add(\"x\");") : String
  <<-JAVA
    class AnonUtils {
        static Set<String> urls(Ctx ctx) {
            for (Map.Entry<RequestMappingInfo, HandlerMethod> e : mapping.getHandlerMethods().entrySet()) {
                if (#{cond || "e.getValue().#{reader} != null"}) { #{add} }
            }
            return out;
        }
        #{extra}
    }
    JAVA
end

def marker_chain(rule : String = "permitAll()", feed : String = "AnonUtils.urls(ctx)", before : String = "", head : String = "") : String
  <<-JAVA
    @EnableWebSecurity
    class SecurityConfig {
        SecurityFilterChain chain(HttpSecurity http) throws Exception {
            Set<String> anonymousUrls = #{feed};
            http#{head}.authorizeRequests()
                #{before}
                .antMatchers(HttpMethod.GET, anonymousUrls.toArray(new String[0])).#{rule}
                .anyRequest().authenticated();
            return http.build();
        }
    }
    JAVA
end

def marker_files(reader : String = "getMethodAnnotation(AnonymousAccess.class)", chain : String = marker_chain, extra : String = "", cond : String? = nil, add : String = "out.add(\"x\");") : Hash(String, String)
  {
    "#{MARKER_DIR}AnonymousAccess.java"     => "public @interface AnonymousAccess {}\n",
    "#{MARKER_DIR}AnonymousGetMapping.java" => "@AnonymousAccess\n@RequestMapping(method = RequestMethod.GET)\npublic @interface AnonymousGetMapping {}\n",
    "#{MARKER_DIR}Unrelated.java"           => "@RequestMapping(method = RequestMethod.GET)\npublic @interface UnrelatedGetMapping {}\n",
    "#{MARKER_DIR}AnonUtils.java"           => marker_utils(reader, extra, cond, add),
    "#{MARKER_DIR}SecurityConfig.java"      => chain,
  }
end

describe "SpringAuthTagger annotation-collected permitAll" do
  controller = <<-JAVA
    class C {
        @AnonymousGetMapping("/open")
        public String open() { return "x"; }

        @GetMapping("/closed")
        public String closed() { return "x"; }

        @AnonymousGetMapping("/both")
        @PreAuthorize("hasRole('ADMIN')")
        public String both() { return "x"; }

        @UnrelatedGetMapping("/unrelated")
        public String unrelated() { return "x"; }

        @AnonymousAccess
        @GetMapping("/direct")
        public String direct() { return "x"; }
    }
    JAVA
  routes = {
    "GET /open"      => "#{MARKER_DIR}C.java:2",
    "GET /closed"    => "#{MARKER_DIR}C.java:5",
    "GET /both"      => "#{MARKER_DIR}C.java:8",
    "GET /unrelated" => "#{MARKER_DIR}C.java:12",
    "GET /direct"    => "#{MARKER_DIR}C.java:16",
  }
  with_controller = ->(files : Hash(String, String)) { files.merge({"#{MARKER_DIR}C.java" => controller}) }

  it "reads the annotation the permitAll matcher is collected from, meta-annotations included" do
    tags = run_spring_markers(with_controller.call(marker_files), routes)
    tags["GET /open"].should be_empty
    tags["GET /direct"].should be_empty
    tags["GET /closed"].should eq([ANY_REQUEST])
    tags["GET /unrelated"].should eq([ANY_REQUEST])
    tags["GET /both"].should eq(["Protected by Spring @PreAuthorize"])
  end

  it "keeps the guard when the collected matcher is not a permitAll" do
    tags = run_spring_markers(with_controller.call(marker_files(chain: marker_chain(rule: "authenticated()"))), routes)
    tags["GET /open"].should eq([ANY_REQUEST])
  end

  it "keeps the guard when the feeding method does not read the annotation" do
    tags = run_spring_markers(with_controller.call(marker_files(reader: "getMethodAnnotation(Other.class)")), routes)
    tags["GET /open"].should eq([ANY_REQUEST])
  end

  it "keeps the guard for a verb the collected matcher does not name" do
    post = <<-JAVA
      class P {
          @AnonymousAccess
          @PostMapping("/p")
          public String p() { return "x"; }
      }
      JAVA
    tags = run_spring_markers(marker_files.merge({"#{MARKER_DIR}P.java" => post}), {"POST /p" => "#{MARKER_DIR}P.java:3"})
    tags["POST /p"].should eq([ANY_REQUEST])
  end

  it "keeps the guard when the feeding method reads more than one annotation" do
    reader = "getMethodAnnotation(AnonymousAccess.class) != null || e.getValue().getMethodAnnotation(AdminOnly.class)"
    tags = run_spring_markers(with_controller.call(marker_files(reader: reader)), routes)
    tags["GET /open"].should eq([ANY_REQUEST])
  end

  it "ties the read to the method feeding the matcher, not to the class" do
    # `publicPaths` reads a property; `needsLogin` in the same class reads @LoginRequired
    utils = <<-JAVA
      class SecurityUtils {
          static String[] publicPaths(Environment env) {
              return env.getProperty("app.public-paths", String[].class);
          }
          static boolean needsLogin(HandlerMethod h) {
              return h.hasMethodAnnotation(LoginRequired.class);
          }
      }
      JAVA
    me = <<-JAVA
      class M {
          @LoginRequired
          @GetMapping("/me")
          public String me() { return "x"; }
      }
      JAVA
    files = {
      "#{MARKER_DIR}SecurityUtils.java"  => utils,
      "#{MARKER_DIR}SecurityConfig.java" => marker_chain(feed: "SecurityUtils.publicPaths(env)"),
      "#{MARKER_DIR}M.java"              => me,
    }
    run_spring_markers(files, {"GET /me" => "#{MARKER_DIR}M.java:3"})["GET /me"].should eq([ANY_REQUEST])
  end

  it "does not follow plain reflection into meta-annotations" do
    tags = run_spring_markers(with_controller.call(marker_files(reader: "isAnnotationPresent(AnonymousAccess.class)")), routes)
    tags["GET /direct"].should be_empty
    tags["GET /open"].should eq([ANY_REQUEST])
  end

  it "does not read an annotation in a block comment or a string" do
    source = <<-JAVA
      class B {
          /*
           * @AnonymousAccess
           */
          @GetMapping("/block")
          public String block() { return "x"; }

          @GetMapping(value = "/str", produces = "@AnonymousAccess")
          public String str() { return "x"; }
      }
      JAVA
    tags = run_spring_markers(marker_files.merge({"#{MARKER_DIR}B.java" => source}), {"GET /block" => "#{MARKER_DIR}B.java:5", "GET /str" => "#{MARKER_DIR}B.java:9"})
    tags["GET /block"].should eq([ANY_REQUEST])
    tags["GET /str"].should eq([ANY_REQUEST])
  end

  it "keeps the guard of a chain whose matcher does not cover the handler" do
    two_chains = <<-JAVA
      @EnableWebSecurity
      class SecurityConfig {
          @Bean
          @Order(1)
          SecurityFilterChain api(HttpSecurity http) throws Exception {
              Set<String> anonymousUrls = AnonUtils.urls(ctx);
              http.antMatcher("/api/**").authorizeRequests()
                  .antMatchers(HttpMethod.GET, anonymousUrls.toArray(new String[0])).permitAll()
                  .anyRequest().authenticated();
              return http.build();
          }
          @Bean
          @Order(2)
          SecurityFilterChain web(HttpSecurity http) throws Exception {
              http.authorizeRequests().anyRequest().authenticated();
              return http.build();
          }
      }
      JAVA
    source = <<-JAVA
      class W {
          @AnonymousAccess
          @GetMapping("/api/open")
          public String apiOpen() { return "x"; }

          @AnonymousAccess
          @GetMapping("/web/x")
          public String webX() { return "x"; }
      }
      JAVA
    tags = run_spring_markers(marker_files(chain: two_chains).merge({"#{MARKER_DIR}W.java" => source}), {"GET /api/open" => "#{MARKER_DIR}W.java:3", "GET /web/x" => "#{MARKER_DIR}W.java:7"})
    tags["GET /api/open"].should be_empty
    tags["GET /web/x"].should eq([ANY_REQUEST])
  end

  it "reads only a positive test guarding an add, never a whitelist-by-default collector" do
    me = <<-JAVA
      class M {
          @AnonymousAccess
          @GetMapping("/me")
          public String me() { return "x"; }
      }
      JAVA
    {
      "== null add"      => {"e.getValue().getMethodAnnotation(AnonymousAccess.class) == null", "out.add(\"x\");"},
      "negated has"      => {"!e.getValue().hasMethodAnnotation(AnonymousAccess.class)", "out.add(\"x\");"},
      "!= null continue" => {"e.getValue().getMethodAnnotation(AnonymousAccess.class) != null", "continue;"},
      "has continue"     => {"e.getValue().hasMethodAnnotation(AnonymousAccess.class)", "continue;"},
      "and-ed test"      => {"e.getValue().getMethodAnnotation(AnonymousAccess.class) != null || other()", "out.add(\"x\");"},
    }.each do |label, (cond, add)|
      files = marker_files(cond: cond, add: add).merge({"#{MARKER_DIR}M.java" => me})
      run_spring_markers(files, {"GET /me" => "#{MARKER_DIR}M.java:3"})["GET /me"].should eq([ANY_REQUEST]), label
    end
  end

  it "reads a bare positive has-test and a variable tested with != null" do
    me = <<-JAVA
      class M {
          @AnonymousAccess
          @GetMapping("/me")
          public String me() { return "x"; }
      }
      JAVA
    has = marker_files(cond: "e.getValue().hasMethodAnnotation(AnonymousAccess.class)").merge({"#{MARKER_DIR}M.java" => me})
    run_spring_markers(has, {"GET /me" => "#{MARKER_DIR}M.java:3"})["GET /me"].should be_empty
    variable = marker_utils("x").sub("if (e.getValue().x != null) { out.add(\"x\"); }", "AnonymousAccess a = e.getValue().getMethodAnnotation(AnonymousAccess.class);\n if (null != a) { out.add(\"x\"); }")
    files = marker_files.merge({"#{MARKER_DIR}AnonUtils.java" => variable, "#{MARKER_DIR}M.java" => me})
    run_spring_markers(files, {"GET /me" => "#{MARKER_DIR}M.java:3"})["GET /me"].should be_empty
  end

  it "resolves the matcher variable inside its own chain only" do
    chains = <<-JAVA
      @EnableWebSecurity
      class SecurityConfig {
          @Bean
          @Order(1)
          SecurityFilterChain api(HttpSecurity http) throws Exception {
              Set<String> urls = AnonUtils.urls(ctx);
              http.antMatcher("/api/**").authorizeRequests()
                  .antMatchers(urls.toArray(new String[0])).permitAll()
                  .anyRequest().authenticated();
              return http.build();
          }
          @Bean
          @Order(2)
          SecurityFilterChain web(HttpSecurity http) throws Exception {
              Set<String> urls = props.getWhitelist();
              http.authorizeRequests()
                  .antMatchers(urls.toArray(new String[0])).permitAll()
                  .anyRequest().authenticated();
              return http.build();
          }
      }
      JAVA
    source = <<-JAVA
      class W {
          @AnonymousAccess
          @GetMapping("/api/open")
          public String apiOpen() { return "x"; }

          @AnonymousAccess
          @GetMapping("/web/x")
          public String webX() { return "x"; }
      }
      JAVA
    tags = run_spring_markers(marker_files(chain: chains).merge({"#{MARKER_DIR}W.java" => source}), {"GET /api/open" => "#{MARKER_DIR}W.java:3", "GET /web/x" => "#{MARKER_DIR}W.java:7"})
    tags["GET /api/open"].should be_empty
    tags["GET /web/x"].should eq([ANY_REQUEST])
  end

  it "respects first-match order: an earlier catch-all keeps the guard" do
    chain = marker_chain(before: ".antMatchers(\"/**\").authenticated()")
    tags = run_spring_markers(with_controller.call(marker_files(chain: chain)), routes)
    tags["GET /open"].first.should contain("authenticated via antMatchers(\"/**\")")
  end
end

describe "SpringAuthTagger Shiro" do
  config = ->(entries : String) do
    {"#{MARKER_DIR}ShiroConfig.java" => <<-JAVA}
      class ShiroConfig {
          ShiroFilterFactoryBean factory(SecurityManager sm) {
              ShiroFilterFactoryBean bean = new ShiroFilterFactoryBean();
              Map<String, String> filterChainDefinitionMap = new LinkedHashMap<String, String>();
              #{entries}
              bean.setFilterChainDefinitionMap(filterChainDefinitionMap);
              return bean;
          }
      }
      JAVA
  end
  routes = {
    "GET /admin/auth/login" => "#{MARKER_DIR}C.java:1",
    "GET /admin/users"      => "#{MARKER_DIR}C.java:1",
    "GET /public"           => "#{MARKER_DIR}C.java:1",
  }
  controller = {"#{MARKER_DIR}C.java" => "class C {}\n"}

  it "reads the filter chain map: anon entries open, authc entries guarded" do
    entries = <<-JAVA
      filterChainDefinitionMap.put("/admin/auth/login", "anon");
      filterChainDefinitionMap.put("/admin/**", "authc");
      JAVA
    tags = run_spring_markers(config.call(entries).merge(controller), routes)
    tags["GET /admin/auth/login"].should be_empty
    tags["GET /admin/users"].first.should start_with("Protected by Shiro authc")
    tags["GET /public"].should be_empty
  end

  it "takes the first matching entry in insertion order" do
    entries = <<-JAVA
      filterChainDefinitionMap.put("/admin/*", "authc");
      filterChainDefinitionMap.put("/admin/login", "anon");
      filterChainDefinitionMap.put("/user/**/edit", "authc");
      filterChainDefinitionMap.put("/user/profile/**", "anon");
      filterChainDefinitionMap.put("/dup", "anon");
      filterChainDefinitionMap.put("/dup", "authc");
      filterChainDefinitionMap.put("/**", "anon");
      JAVA
    tags = run_spring_markers(config.call(entries).merge(controller), {
      "GET /admin/login"       => "#{MARKER_DIR}C.java:1",
      "GET /admin/a/b"         => "#{MARKER_DIR}C.java:1",
      "GET /user/profile/edit" => "#{MARKER_DIR}C.java:1",
      "GET /user/profile/view" => "#{MARKER_DIR}C.java:1",
      "GET /dup"               => "#{MARKER_DIR}C.java:1",
    })
    tags["GET /admin/login"].first.should contain("(\"/admin/*\")")
    tags["GET /admin/a/b"].should be_empty
    tags["GET /user/profile/edit"].first.should contain("(\"/user/**/edit\")")
    tags["GET /user/profile/view"].should be_empty
    tags["GET /dup"].first.should start_with("Protected by Shiro authc")
  end

  it "reads addPathDefinition and ignores puts on other maps" do
    entries = <<-JAVA
      chain.addPathDefinition("/admin/**", "authc");
      labels.put("/public", "jwt");
      JAVA
    tags = run_spring_markers(config.call(entries).merge(controller), routes)
    tags["GET /admin/users"].first.should start_with("Protected by Shiro authc")
    tags["GET /public"].should be_empty
  end

  it "limits a custom filter to its own pattern and names it as Shiro" do
    entries = <<-JAVA
      filterChainDefinitionMap.put("/admin/**", "jwt");
      JAVA
    tags = run_spring_markers(config.call(entries).merge(controller), routes)
    tags["GET /admin/users"].first.should start_with("Protected by Shiro filter \"jwt\"")
    tags["GET /public"].should be_empty
  end

  it "reads Shiro method annotations" do
    source = <<-JAVA
      class S {
          @RequiresPermissions("a:b")
          @GetMapping("/perm")
          public String perm() { return "x"; }

          @RequiresGuest
          @GetMapping("/guest")
          public String guest() { return "x"; }

          @GetMapping("/plain")
          public String plain() { return "x"; }
      }
      JAVA
    tags = run_spring_markers({"#{MARKER_DIR}S.java" => source}, {
      "GET /perm"  => "#{MARKER_DIR}S.java:3",
      "GET /guest" => "#{MARKER_DIR}S.java:7",
      "GET /plain" => "#{MARKER_DIR}S.java:10",
    })
    tags["GET /perm"].should eq(["Protected by Shiro @RequiresPermissions"])
    tags["GET /guest"].should be_empty
    tags["GET /plain"].should be_empty
  end
end

describe "SpringAuthTagger argument-resolver principal" do
  resolver_files = ->(returns_null : Bool, registered : Bool) do
    files = {
      "#{MARKER_DIR}LoginUser.java"         => "public @interface LoginUser {}\n",
      "#{MARKER_DIR}LoginUserResolver.java" => <<-JAVA,
        public class LoginUserResolver implements HandlerMethodArgumentResolver {
            public boolean supportsParameter(MethodParameter parameter) {
                return parameter.hasParameterAnnotation(LoginUser.class);
            }
            public Object resolveArgument(MethodParameter parameter) {
                String token = request.getHeader("X-Token");
                #{returns_null ? "if (token == null) { return null; }" : "if (token == null) { return Integer.valueOf(0); }"}
                return UserTokenManager.getUserId(token);
            }
        }
        JAVA
    }
    if registered
      files["#{MARKER_DIR}WebConfig.java"] = <<-JAVA
        class WebConfig implements WebMvcConfigurer {
            public void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) {
                resolvers.add(new LoginUserResolver());
            }
        }
        JAVA
    end
    files
  end
  controller = <<-JAVA
    class W {
        private OrderService orderService;
        @GetMapping("list")
        public Object list(@LoginUser Integer userId) {
            if (userId == null) {
                return ResponseUtil.unlogin();
            }
            return 1;
        }

        @GetMapping("count")
        public Object count(@LoginUser Integer userId) {
            if (userId == null) {
                return ResponseUtil.ok(0);
            }
            return 1;
        }

        @GetMapping("late")
        public Object late(@LoginUser Integer userId) {
            audit.record();
            if (userId == null) {
                return ResponseUtil.unlogin();
            }
            return 1;
        }

        @GetMapping("order")
        public Object order(@LoginUser Integer userId, @RequestParam Integer page) {
            return orderService.list(userId, page);
        }

        @GetMapping("loose")
        public Object loose(@LoginUser Integer userId, @RequestParam Integer page) {
            return orderService.loose(userId, page);
        }

        @GetMapping("overload")
        public Object overload(@LoginUser Integer userId, @RequestParam String sn) {
            return orderService.detail(sn, userId);
        }

        @GetMapping("overloads")
        public Object overloads(@LoginUser Integer userId, @RequestParam String sn) {
            return orderService.both(sn, userId);
        }
    }
    JAVA
  service = <<-JAVA
    @Service
    public class OrderService {
        public Object list(Integer userId, @RequestParam(defaultValue = "1") Integer page) {
            if (userId == null) {
                return ResponseUtil.unlogin();
            }
            return 1;
        }

        public Object loose(Integer userId, Integer page) {
            return query(userId);
        }

        public Object detail(Integer orderId, Integer userId) {
            if (userId == null) {
                return ResponseUtil.unlogin();
            }
            return 1;
        }

        public Object detail(String orderSn, Integer userId) {
            return find(orderSn);
        }

        public Object both(Integer orderId, Integer userId) {
            if (userId == null) {
                return ResponseUtil.unlogin();
            }
            return 1;
        }

        public Object both(String orderSn, Integer userId) {
            if (userId == null) {
                return ResponseUtil.unlogin();
            }
            return 2;
        }
    }
    JAVA
  routes = {
    "GET /list"      => "#{MARKER_DIR}W.java:3",
    "GET /count"     => "#{MARKER_DIR}W.java:11",
    "GET /late"      => "#{MARKER_DIR}W.java:19",
    "GET /order"     => "#{MARKER_DIR}W.java:28",
    "GET /loose"     => "#{MARKER_DIR}W.java:33",
    "GET /overload"  => "#{MARKER_DIR}W.java:38",
    "GET /overloads" => "#{MARKER_DIR}W.java:43",
  }
  refusal = "Protected by in-handler check: refuses an anonymous caller (userId == null)"

  it "reads a registered null-returning login annotation, in the handler or one service hop away" do
    tags = run_spring_markers(resolver_files.call(true, true).merge({"#{MARKER_DIR}W.java" => controller, "#{MARKER_DIR}OrderService.java" => service}), routes)
    tags["GET /list"].should eq([refusal])
    tags["GET /order"].should eq([refusal])
    tags["GET /overloads"].should eq([refusal])
    tags["GET /count"].should be_empty
    tags["GET /late"].should be_empty
    tags["GET /loose"].should be_empty
    # one overload of `detail` does not refuse
    tags["GET /overload"].should be_empty
  end

  it "does nothing when the resolver never returns null" do
    run_spring_markers(resolver_files.call(false, true).merge({"#{MARKER_DIR}W.java" => controller}), routes)["GET /list"].should be_empty
  end

  it "does nothing when no configuration registers the resolver" do
    run_spring_markers(resolver_files.call(true, false).merge({"#{MARKER_DIR}W.java" => controller}), routes)["GET /list"].should be_empty
  end

  it "does not take a same-named annotation of another package for the resolver's" do
    other = "package com.adm;\npublic @interface LoginUser {}\n"
    admin = "package com.adm;\nclass A {\n    @GetMapping(\"/me\")\n    public Object me(@LoginUser Integer userId) {\n        if (userId == null) {\n            return ResponseUtil.unlogin();\n        }\n        return 1;\n    }\n}\n"
    files = resolver_files.call(true, true).transform_values { |source| "package com.example;\n#{source}" }
    files["src/main/java/com/adm/LoginUser.java"] = other
    files["src/main/java/com/adm/A.java"] = admin
    run_spring_markers(files, {"GET /me" => "src/main/java/com/adm/A.java:3"})["GET /me"].should be_empty
  end

  it "reads delegated refusals in linear time" do
    build = ->(count : Int32) do
      handlers = (0...count).map do |i|
        "    @GetMapping(\"h#{i}\")\n    public Object h#{i}(@LoginUser Integer userId) {\n        return orderService.m#{i}(userId);\n    }\n"
      end.join("\n")
      methods = (0...count).map do |i|
        "    public Object m#{i}(Integer userId) {\n        if (userId == null) {\n            return ResponseUtil.unlogin();\n        }\n        return #{i};\n    }\n"
      end.join("\n")
      files = resolver_files.call(true, true).merge({
        "#{MARKER_DIR}W.java"            => "class W {\n    private OrderService orderService;\n#{handlers}}\n",
        "#{MARKER_DIR}OrderService.java" => "@Service\npublic class OrderService {\n#{methods}}\n",
      })
      routes = (0...count).to_h { |i| {"GET /h#{i}", "#{MARKER_DIR}W.java:#{3 + i * 5}"} }
      started = Time.instant
      tags = run_spring_markers(files, routes)
      tags["GET /h#{count - 1}"].size.should eq(1)
      (Time.instant - started).total_seconds
    end
    build.call(50) # warm up
    small = (0...3).min_of { build.call(500) }
    large = (0...3).min_of { build.call(2000) }
    # 4x the handlers: linear is ~4x, quadratic ~16x
    (large / small).should be < 10.0
  end
end
