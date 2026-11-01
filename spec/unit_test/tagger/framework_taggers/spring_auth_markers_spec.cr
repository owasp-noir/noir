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

MARKER_DIR = "src/main/java/com/example/"

def marker_files(rule : String = "permitAll()", reader : String = "getMethodAnnotation(AnonymousAccess.class)", feed : String = "AnonUtils.urls(ctx)") : Hash(String, String)
  {
    "#{MARKER_DIR}AnonymousAccess.java"     => "public @interface AnonymousAccess {}\n",
    "#{MARKER_DIR}AnonymousGetMapping.java" => "@AnonymousAccess\n@RequestMapping(method = RequestMethod.GET)\npublic @interface AnonymousGetMapping {}\n",
    "#{MARKER_DIR}Unrelated.java"           => "@RequestMapping(method = RequestMethod.GET)\npublic @interface UnrelatedGetMapping {}\n",
    "#{MARKER_DIR}AnonUtils.java"           => "class AnonUtils {\n  static Set<String> urls(Ctx ctx) {\n    return h.#{reader};\n  }\n}\n",
    "#{MARKER_DIR}SecurityConfig.java"      => <<-JAVA,
     @EnableWebSecurity
     class SecurityConfig {
         SecurityFilterChain chain(HttpSecurity http) throws Exception {
             Set<String> anonymousUrls = #{feed};
             http.authorizeRequests()
                 .antMatchers(HttpMethod.GET, anonymousUrls.toArray(new String[0])).#{rule}
                 .anyRequest().authenticated();
             return http.build();
         }
     }
     JAVA
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

  it "reads the annotation the permitAll matcher is collected from, meta-annotations included" do
    tags = run_spring_markers(marker_files.merge({"#{MARKER_DIR}C.java" => controller}), routes)
    tags["GET /open"].should be_empty
    tags["GET /direct"].should be_empty
    tags["GET /closed"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
    tags["GET /unrelated"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
    tags["GET /both"].should eq(["Protected by Spring @PreAuthorize"])
  end

  it "keeps the guard when the collected matcher is not a permitAll" do
    tags = run_spring_markers(marker_files(rule: "authenticated()").merge({"#{MARKER_DIR}C.java" => controller}), routes)
    tags["GET /open"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
  end

  it "keeps the guard when the matcher is fed by a class that does not read the annotation" do
    tags = run_spring_markers(marker_files(reader: "getMethodAnnotation(Other.class)").merge({"#{MARKER_DIR}C.java" => controller}), routes)
    tags["GET /open"].should eq(["Protected by Spring Security authenticated via anyRequest()"])
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

  it "ignores an entry an earlier broader one shadows (first match wins)" do
    entries = <<-JAVA
      filterChainDefinitionMap.put("/admin/**", "authc");
      filterChainDefinitionMap.put("/admin/auth/login", "anon");
      JAVA
    tags = run_spring_markers(config.call(entries).merge(controller), routes)
    tags["GET /admin/auth/login"].first.should start_with("Protected by Shiro authc")
  end

  it "does not read a narrower earlier entry as shadowing a broader later one" do
    entries = <<-JAVA
      filterChainDefinitionMap.put("/admin/*", "anon");
      filterChainDefinitionMap.put("/admin/**", "authc");
      JAVA
    tags = run_spring_markers(config.call(entries).merge(controller), {"GET /admin/a/b" => "#{MARKER_DIR}C.java:1"})
    tags["GET /admin/a/b"].first.should start_with("Protected by Shiro authc")
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

  it "does not guess at a custom filter" do
    entries = <<-JAVA
      filterChainDefinitionMap.put("/admin/**", "jwt");
      JAVA
    tags = run_spring_markers(config.call(entries).merge(controller), routes)
    tags["GET /admin/users"].first.should contain("Shiro filter \"jwt\"")
    tags["GET /public"].first.should contain("Shiro filter \"jwt\"")
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
  resolver = ->(returns_null : Bool) do
    {"#{MARKER_DIR}LoginUserResolver.java" => <<-JAVA}
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
  end
  controller = <<-JAVA
    class W {
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
    }
    JAVA
  routes = {
    "GET /list"  => "#{MARKER_DIR}W.java:2",
    "GET /count" => "#{MARKER_DIR}W.java:10",
    "GET /late"  => "#{MARKER_DIR}W.java:18",
    "GET /order" => "#{MARKER_DIR}W.java:28",
    "GET /loose" => "#{MARKER_DIR}W.java:33",
  }
  files = ->(returns_null : Bool) do
    resolver.call(returns_null).merge({"#{MARKER_DIR}W.java" => controller.sub("class W {", "class W {\n    private OrderService orderService;").gsub(/^/m, ""), "#{MARKER_DIR}OrderService.java" => service})
  end

  it "reads a custom login annotation whose resolver returns null, in the handler or one service hop away" do
    # the injected field line shifts every route by one
    shifted = routes.transform_values { |location| "#{location.split(':')[0]}:#{location.split(':')[1].to_i + 1}" }
    tags = run_spring_markers(files.call(true), shifted)
    tags["GET /list"].should eq(["Protected by in-handler check: refuses an anonymous caller (userId == null)"])
    tags["GET /order"].should eq(["Protected by in-handler check: refuses an anonymous caller (userId == null)"])
    tags["GET /count"].should be_empty
    tags["GET /late"].should be_empty
    tags["GET /loose"].should be_empty
  end

  it "does nothing when the resolver never returns null" do
    shifted = routes.transform_values { |location| "#{location.split(':')[0]}:#{location.split(':')[1].to_i + 1}" }
    run_spring_markers(files.call(false), shifted)["GET /list"].should be_empty
  end
end
