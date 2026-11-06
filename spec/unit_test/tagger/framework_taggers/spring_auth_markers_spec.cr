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

  it "requires the guarded add to fill the collection the method returns" do
    me = <<-JAVA
      class M {
          @AnonymousAccess
          @GetMapping("/me")
          public String me() { return "x"; }
      }
      JAVA
    loop_head = "for (Map.Entry<RequestMappingInfo, HandlerMethod> e : mapping.getHandlerMethods().entrySet())"
    collectors = {
      "else branch adds"           => "static Set<String> urls(Ctx c) {\n Set<String> urls = new HashSet<>(); Set<String> secured = new HashSet<>();\n #{loop_head} {\n if (e.getValue().getMethodAnnotation(AnonymousAccess.class) != null) { secured.add(\"x\"); } else { urls.add(\"x\"); }\n }\n return urls;\n }",
      "all minus secured"          => "static Set<String> urls(Ctx c) {\n Set<String> all = new HashSet<>(); Set<String> secured = new HashSet<>();\n #{loop_head} {\n all.add(\"x\");\n if (e.getValue().getMethodAnnotation(AnonymousAccess.class) != null) { secured.add(\"x\"); }\n }\n all.removeAll(secured);\n return all;\n }",
      "reassigned to a difference" => "static Set<String> urls(Ctx c) {\n Set<String> urls = new HashSet<>(); Set<String> all = allPaths(c);\n #{loop_head} {\n if (e.getValue().getMethodAnnotation(AnonymousAccess.class) != null) { urls.add(\"x\"); }\n }\n Set<String> secured = urls;\n urls = Sets.difference(all, secured);\n return urls;\n }",
      "alias gets the rest"        => "static Set<String> urls(Ctx c) {\n Set<String> urls = new HashSet<>(); Set<String> all = allPaths(c);\n #{loop_head} {\n if (e.getValue().getMethodAnnotation(AnonymousAccess.class) != null) { urls.add(\"x\"); }\n }\n Set<String> s = urls;\n s.addAll(all);\n return urls;\n }",
      "add outside the guard"      => "static Set<String> urls(Ctx c) {\n Set<String> urls = new HashSet<>();\n urls.add(\"/seed\");\n #{loop_head} {\n if (e.getValue().getMethodAnnotation(AnonymousAccess.class) != null) { urls.add(\"x\"); }\n }\n return urls;\n }",
    }
    collectors.each do |label, method|
      files = marker_files.merge({"#{MARKER_DIR}AnonUtils.java" => "class AnonUtils {\n #{method}\n}\n", "#{MARKER_DIR}M.java" => me})
      run_spring_markers(files, {"GET /me" => "#{MARKER_DIR}M.java:3"})["GET /me"].should eq([ANY_REQUEST]), label
    end
    wired = "static Map<String, Set<String>> urls(Ctx c) {\n Map<String, Set<String>> out = new HashMap<>(); Set<String> get = new HashSet<>();\n #{loop_head} {\n if (e.getValue().getMethodAnnotation(AnonymousAccess.class) != null) { get.addAll(patterns(e)); }\n }\n out.put(\"GET\", get);\n return out;\n }"
    files = marker_files.merge({"#{MARKER_DIR}AnonUtils.java" => "class AnonUtils {\n #{wired}\n}\n", "#{MARKER_DIR}M.java" => me})
    run_spring_markers(files, {"GET /me" => "#{MARKER_DIR}M.java:3"})["GET /me"].should be_empty
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
      perf_routes = (0...count).to_h { |i| {"GET /h#{i}", "#{MARKER_DIR}W.java:#{3 + i * 5}"} }
      started = Time.instant
      tags = run_spring_markers(files, perf_routes)
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

describe "SpringAuthTagger refusing argument resolver" do
  # `body` is the whole resolveArgument; `handler` the annotated parameter.
  resolver = ->(body : String, handler : String, extra : Hash(String, String)) do
    {
      "#{MARKER_DIR}NeedLogin.java"         => "public @interface NeedLogin { boolean required() default true; }\n",
      "#{MARKER_DIR}Fail.java"              => "public class Fail { public static void fail(String m) { throw new RuntimeException(m); } }\n",
      "#{MARKER_DIR}NeedLoginResolver.java" => <<-JAVA,
        public class NeedLoginResolver implements HandlerMethodArgumentResolver {
            public boolean supportsParameter(MethodParameter parameter) {
                return parameter.hasParameterAnnotation(NeedLogin.class);
            }
            public Object resolveArgument(MethodParameter parameter, NativeWebRequest request) {
        #{body}
            }
        }
        JAVA
      "#{MARKER_DIR}WebConfig.java" => <<-JAVA,
        class WebConfig {
            @Autowired private NeedLoginResolver needLoginResolver;
            public void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) {
                resolvers.add(needLoginResolver);
            }
        }
        JAVA
      "#{MARKER_DIR}C.java" => <<-JAVA,
        class C {
            @GetMapping("/me")
            public Object me(#{handler} User user) { return user; }
            @GetMapping("/open")
            public Object open() { return 1; }
        }
        JAVA
    }.merge(extra)
  end
  routes = {"GET /me" => "#{MARKER_DIR}C.java:2", "GET /open" => "#{MARKER_DIR}C.java:4"}
  none = {} of String => String
  guarded = ->(body : String, handler : String, extra : Hash(String, String)) { run_spring_markers(resolver.call(body, handler, extra), routes)["GET /me"].size }
  header = "String token = request.getHeader(\"token\");"

  it "guards a resolver that throws when the token is absent" do
    guarded.call("#{header} if (token == null) { throw new IllegalStateException(); } return lookup(token);", "@NeedLogin", none).should eq(1)
    guarded.call("#{header} if (token != null && token.length() == 8) { return lookup(token); } else { Fail.fail(\"login\"); } return null;", "@NeedLogin", none).should eq(1)
    run_spring_markers(resolver.call("#{header} if (token == null) { throw new IllegalStateException(); } return lookup(token);", "@NeedLogin", none), routes)["GET /open"].should be_empty
  end

  it "guards the newbee-mall resolver shapes" do
    admin = <<-JAVA
      if (parameter.getParameterAnnotation(NeedLogin.class) instanceof NeedLogin) {
          #{header}
          if (null != token && !"".equals(token) && token.length() == 32) {
              AdminToken adminToken = tokenMapper.selectByToken(token);
              if (adminToken == null) {
                  Fail.fail("not logged in");
              } else if (adminToken.getExpireTime().getTime() <= System.currentTimeMillis()) {
                  Fail.fail("expired");
              }
              return adminToken;
          } else {
              Fail.fail("not logged in");
          }
      }
      return null;
      JAVA
    mall = <<-JAVA
      if (parameter.getParameterAnnotation(NeedLogin.class) instanceof NeedLogin) {
          User user = null;
          #{header}
          if (null != token && !"".equals(token)) {
              UserToken userToken = tokenMapper.selectByToken(token);
              if (userToken == null || userToken.getExpireTime().getTime() <= System.currentTimeMillis()) {
                  Fail.fail("expired");
              }
              user = userMapper.selectByPrimaryKey(userToken.getUserId());
              if (user == null) {
                  Fail.fail("no user");
              }
              if (user.getLockedFlag().intValue() == 1) {
                  Fail.fail("locked");
              }
              return user;
          } else {
              Fail.fail("not logged in");
          }
      }
      return null;
      JAVA
    guarded.call(admin, "@NeedLogin", none).should eq(1)
    guarded.call(mall, "@NeedLogin", none).should eq(1)
  end

  it "does not guard a resolver outside the recognized shape" do
    [
      # a way back without the credential
      "#{header} if (token == null) return null; User u = lookup(token); if (u == null) { throw new IllegalStateException(); } return u;",
      "#{header} if (token == null) { return Guest.INSTANCE; } return lookup(token);",
      "#{header} if (token == null) { return Optional.empty(); } return lookup(token);",
      "#{header} try { return jwt.verify(token); } catch (JwtException e) { return null; }",
      "#{header} switch (mode) { case OPTIONAL: return null; default: break; } if (token == null) { throw new IllegalStateException(); } return lookup(token);",
      "#{header} if (token != null) { User u = userMapper.selectByToken(token); if (u == null) { throw new IllegalStateException(); } return u; } return null;",
      "#{header} if (token != null) { User u = userMapper.selectByToken(token); if (u != null) { return u; } else { Fail.fail(\"bad\"); } } return null;",
      "#{header} if (token != null && token.isBlank()) { throw new IllegalArgumentException(); } return token == null ? null : lookup(token);",
      # the refusal sits under another condition
      "#{header} if (security.isStrict()) { if (token == null) { throw new IllegalStateException(); } } return token == null ? null : lookup(token);",
      "#{header} if (parameter.getParameterType() == User.class) { if (token == null) { throw new IllegalStateException(); } } return null;",
      "#{header} if (debug) { log.info(\"debug\"); } else { if (token == null) { throw new IllegalStateException(); } } return null;",
      "#{header} if (token == null) { if (strict) throw new IllegalStateException(); } return lookup(token);",
      "#{header} if (parameter.getParameterType() == Optional.class) { return Optional.ofNullable(token); } if (token == null) { throw new IllegalStateException(); } return lookup(token);",
      "#{header} if (token == null) { throw new IllegalStateException(); } if (admin) { return lookup(token); } return null;",
      "#{header} try { if (token == null) { throw new IllegalStateException(); } return lookup(token); } catch (IllegalStateException e) { log.warn(\"anonymous\"); } return null;",
      "for (String h : headers) { String token = request.getHeader(h); if (token == null) { throw new IllegalStateException(); } } return null;",
      "#{header} Runnable r = () -> { if (token == null) { throw new IllegalStateException(); } }; return null;",
      "#{header} new Thread(new Runnable() { public void run() { if (token == null) { throw new IllegalStateException(); } } }); return null;",
      # the credential is replaced
      "#{header} if (token == null) { token = GUEST_TOKEN; } User u = lookup(token); if (u == null) { throw new IllegalStateException(); } return u;",
      "#{header} token = token == null ? GUEST_TOKEN : token; if (token == null) { throw new IllegalStateException(); } return lookup(token);",
      "String raw = request.getHeader(\"token\"); String token = raw; if (token == null) { throw new IllegalStateException(); } token = token.trim(); return lookup(token);",
      "#{header} if (token == null) { throw new IllegalStateException(); } token = GUEST_TOKEN; return lookup(token);",
      # not a credential
      "String page = request.getParameter(\"page\"); if (page == null) { throw new IllegalArgumentException(); } return Integer.parseInt(page);",
      "String tenant = request.getHeader(\"X-Tenant-Id\"); if (tenant == null) { throw new BadRequestException(); } return tenantService.find(tenant);",
      "Map<String, String> vars = (Map<String, String>) request.getAttribute(HandlerMapping.URI_TEMPLATE_VARIABLES_ATTRIBUTE, 0); Project project = repo.findById(vars.get(\"projectId\")); if (project == null) { throw new NotFoundException(); } return project;",
      "HttpServletRequest req = request.getNativeRequest(HttpServletRequest.class); if (req == null) { throw new IllegalStateException(); } return svc.find(req.getHeader(\"token\"));",
      "MultipartFile file = ((MultipartRequest) request.getNativeRequest()).getFile(\"file\"); if (file == null) { throw new IllegalArgumentException(); } return read(file);",
      "String token = request.getAttribute(\"token\", 0); if (token == null) { throw new IllegalStateException(); } return lookup(token);",
    ].each { |body| guarded.call(body, "@NeedLogin", none).should eq(0) }
  end

  it "does not guard when the annotation or the resolver makes the credential optional" do
    body = "NeedLogin ann = parameter.getParameterAnnotation(NeedLogin.class); #{header} if (token == null && ann.required()) { throw new IllegalStateException(); } return lookup(token);"
    guarded.call(body, "@NeedLogin", none).should eq(0)
    guarded.call("NeedLogin ann = parameter.getParameterAnnotation(NeedLogin.class); boolean need = ann.value(); #{header} if (token == null) { throw new IllegalStateException(); } return lookup(token);", "@NeedLogin", none).should eq(0)
    plain = "#{header} if (token == null) { throw new IllegalStateException(); } return lookup(token);"
    guarded.call(plain, "@NeedLogin(required = false)", none).should eq(0)
    guarded.call(plain, "@NeedLogin(false)", none).should eq(0)
  end

  it "counts a helper's throw only at its top level, resolved by import" do
    try_helper = {"#{MARKER_DIR}TokenUtil.java" => "public class TokenUtil { public static void check() { try { Keys.generate(); } catch (Exception e) { throw new IllegalStateException(e); } } }\n"}
    guarded.call("#{header} if (token == null) { TokenUtil.check(); } return lookup(token);", "@NeedLogin", try_helper).should eq(0)
    if_helper = {"#{MARKER_DIR}TokenUtil.java" => "public class TokenUtil { public static void check() { if (strict) { throw new IllegalStateException(); } } }\n"}
    guarded.call("#{header} if (token == null) { TokenUtil.check(); } return lookup(token);", "@NeedLogin", if_helper).should eq(0)
    # same-package `Errors` throws, the imported one does not
    files = resolver.call("#{header} if (token == null) { Errors.fail(\"login\"); } return lookup(token);", "@NeedLogin", none).transform_values { |source| "package com.example;\n#{source}" }
    files["#{MARKER_DIR}Errors.java"] = "package com.example;\npublic class Errors { public static void fail(String m) { throw new RuntimeException(m); } }\n"
    files["src/main/java/com/other/Errors.java"] = "package com.other;\npublic class Errors { public static void fail(String m) { System.out.println(m); } }\n"
    packaged = {"GET /me" => "#{MARKER_DIR}C.java:3"}
    run_spring_markers(files, packaged)["GET /me"].size.should eq(1)
    files["#{MARKER_DIR}NeedLoginResolver.java"] = files["#{MARKER_DIR}NeedLoginResolver.java"].sub("package com.example;\n", "package com.example;\nimport com.other.Errors;\n")
    run_spring_markers(files, packaged)["GET /me"].should be_empty
  end

  it "keeps the in-handler check of a principal the refusing resolver hands back as null" do
    body = "#{header} if (token == null) { throw new IllegalStateException(); } User u = lookup(token); return null;"
    check = "{ if (user == null) { throw new IllegalStateException(\"login\"); } return user; }"
    files = resolver.call(body, "@NeedLogin(required = false)", none)
    files["#{MARKER_DIR}C.java"] = files["#{MARKER_DIR}C.java"].sub("{ return user; }", check)
    run_spring_markers(files, routes)["GET /me"].should eq(["Protected by in-handler check: refuses an anonymous caller (user == null)"])
    files = resolver.call("CurrentUser cu = parameter.getParameterAnnotation(CurrentUser.class); #{body}", "@CurrentUser", {"#{MARKER_DIR}CurrentUser.java" => "public @interface CurrentUser {}\n"})
    files["#{MARKER_DIR}C.java"] = files["#{MARKER_DIR}C.java"].sub("{ return user; }", check)
    run_spring_markers(files, routes)["GET /me"].should eq(["Protected by in-handler check: refuses an anonymous caller (user == null)"])
  end

  it "reads only a whole credential key, not one that merely contains token or auth" do
    %w[csrfToken X-CSRF-TOKEN captchaToken pageToken deviceToken Idempotency-Token x-request-token-id author access_type].each do |key|
      guarded.call("String v = request.getHeader(\"#{key}\"); if (v == null) { throw new IllegalStateException(); } return v;", "@NeedLogin", none).should eq(0)
    end
    %w[token Authorization X-Auth-Token access_token jwt api-key X-API-KEY ticket].each do |key|
      guarded.call("String v = request.getHeader(\"#{key}\"); if (v == null) { throw new IllegalStateException(); } return lookup(v);", "@NeedLogin", none).should eq(1)
    end
  end

  it "judges each resolver of a file on its own" do
    both = {"#{MARKER_DIR}NeedLoginResolver.java" => <<-JAVA}
      public class NeedLoginResolver {
          static class Strict implements HandlerMethodArgumentResolver {
              public boolean supportsParameter(MethodParameter parameter) { return parameter.hasParameterAnnotation(NeedLogin.class); }
              public Object resolveArgument(MethodParameter parameter, NativeWebRequest request) {
                  String token = request.getHeader("token"); if (token == null) { throw new IllegalStateException(); } return lookup(token);
              }
          }
          static class Lenient implements HandlerMethodArgumentResolver {
              public boolean supportsParameter(MethodParameter parameter) { return parameter.hasParameterAnnotation(OptionalUser.class); }
              public Object resolveArgument(MethodParameter parameter, NativeWebRequest request) { return null; }
          }
      }
      JAVA
    guarded.call("return null;", "@NeedLogin", both).should eq(0)
  end

  it "does not guard a resolver that hands an absent token a guest user or reads String.valueOf" do
    [
      "#{header} if (token == null) { return guestMapper.find(); } return lookup(token);",
      "#{header} if (token == null) { token = GUEST; } return lookup(token);",
      "#{header} User u; if (token == null) { u = guestMapper.find(); } else { u = lookup(token); } return u;",
      "#{header} if (token == null) { Guests.anonymous(); } return lookup(token);",
      "#{header} if (token == null) { Fail.log(\"guest\"); } return lookup(token);",
      "String token = String.valueOf(request.getHeader(\"token\")); if (token == null) { throw new IllegalStateException(); } return lookup(token);",
      "String token = String.valueOf(request.getHeader(\"token\")); if (token.isEmpty()) { throw new IllegalStateException(); } return lookup(token);",
    ].each do |body|
      guarded.call(body, "@NeedLogin", {"#{MARKER_DIR}Guests.java" => "public class Guests { public static void anonymous() { } }\n"}).should eq(0)
    end
  end

  it "reads a resolver body in linear time" do
    tail = " if (token == null) { throw new IllegalStateException(); } return lookup(token);"
    time = ->(body : String) do
      started = Time.instant
      guarded.call(body, "@NeedLogin", none)
      (Time.instant - started).total_seconds
    end
    flat = ->(count : Int32) { "#{header} " + (1..count).map { |i| "if (token.equals(\"v#{i}\")) { x = #{i}; }" }.join(" ") + tail }
    time.call(flat.call(500)) # warm up
    small = (0...3).min_of { time.call(flat.call(4000)) }
    large = (0...3).min_of { time.call(flat.call(16000)) }
    # 4x the conditions: linear is ~4x, quadratic ~16x
    (large / small).should be < 10.0
    nested = "#{header} " + (0...20000).map { |i| "if (token.equals(\"v#{i}\")) { " }.join + "x = 1;" + " }" * 20000 + tail
    time.call(nested).should be < 5
  end
end
