require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

INTERCEPTOR_DIR = "src/main/java/com/example/"

# Run SpringAuthTagger with `interceptor` (the `preHandle` body plus extra
# members) registered on `/api/**`, over GET routes of one controller.
def interceptor_guards(pre_handle : String, members : String = "", extra = {} of String => String, urls = ["/api/items", "/api/login", "/api/open"]) : Hash(String, Array(String))
  interceptor = <<-JAVA
    package com.example;

    import com.example.common.OpenPaths;

    public class AuthInterceptor implements HandlerInterceptor {
        @Override
        public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
    #{pre_handle}
        }
    #{members}
    }
    JAVA
  config = <<-JAVA
    package com.example;

    public class WebConfig implements WebMvcConfigurer {
        @Autowired private AuthInterceptor authInterceptor;

        @Override
        public void addInterceptors(InterceptorRegistry registry) {
            registry.addInterceptor(authInterceptor).addPathPatterns("/api/**");
        }
    }
    JAVA
  controller = "package com.example;\n\n@RestController\npublic class ApiController {\n" +
               urls.map { |url| "    @GetMapping(\"#{url}\")\n    public String x() { return \"\"; }\n" }.join +
               "}\n"
  files = {
    "#{INTERCEPTOR_DIR}AuthInterceptor.java" => interceptor,
    "#{INTERCEPTOR_DIR}WebConfig.java"       => config,
    "#{INTERCEPTOR_DIR}ApiController.java"   => controller,
  }.merge(extra)
  CodeLocator.instance.clear_all
  root = File.tempname("interceptor_allow_list")
  files.each do |relative, source|
    path = File.join(root, relative)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, source)
    CodeLocator.instance.register_path(path)
  end
  options = create_test_options
  options["base"] = YAML::Any.new(root)
  endpoints = urls.map_with_index do |url, i|
    Endpoint.new(url, "GET", [] of Param, Details.new(PathInfo.new(File.join(root, "#{INTERCEPTOR_DIR}ApiController.java"), 5 + i * 2)))
  end
  SpringAuthTagger.new(options).perform(endpoints)
  FileUtils.rm_rf(root)
  urls.zip(endpoints).to_h { |url, endpoint| {"GET #{url}", endpoint.tags.select(&.name.==("auth")).map(&.description)} }
end

RESPONSE_HELPER = <<-JAVA
      private boolean responseTransform(HttpServletResponse response, int code, String msg) throws IOException {
          response.setStatus(code);
          response.getWriter().print(msg);
          return false;
      }
  JAVA

OPEN_PATHS = <<-JAVA
  package com.example.common;

  public class OpenPaths {
      public static final List<String> WHITELIST =
              new ArrayList<>() {
                  {
                      add("/api/login");
                      add("/api/open");
                  }
              };

      public static boolean isOpen(String uri) {
          return WHITELIST.contains(uri);
      }
  }
  JAVA

GUARD = "Protected by Spring HandlerInterceptor AuthInterceptor"

describe "SpringAuthTagger (HandlerInterceptor refusal helpers and allow-lists)" do
  it "reads a 401 handed to a helper that sets the response status" do
    result = interceptor_guards(<<-JAVA, RESPONSE_HELPER)
            if (!authService.check()) {
                return responseTransform(response, 401, "login");
            }
            return HandlerInterceptor.super.preHandle(request, response, handler);
      JAVA
    result["GET /api/items"].should eq([GUARD])
    result["GET /api/login"].should eq([GUARD])
  end

  it "lets through the URIs of an allow-list checked before the refusal" do
    extra = {"#{INTERCEPTOR_DIR}common/OpenPaths.java" => OPEN_PATHS}
    {
      "OpenPaths.WHITELIST.contains(request.getRequestURI())",
      "OpenPaths.isOpen(request.getRequestURI())",
    }.each do |cond|
      result = interceptor_guards(<<-JAVA, RESPONSE_HELPER, extra)
              if (#{cond}) {
                  return HandlerInterceptor.super.preHandle(request, response, handler);
              }
              if (!authService.check()) {
                  return responseTransform(response, 401, "login");
              }
              return true;
        JAVA
      result["GET /api/items"].should eq([GUARD])
      result["GET /api/login"].should be_empty
      result["GET /api/open"].should be_empty
    end
  end

  it "reads an allow-list field of the interceptor itself, for a direct refusal too" do
    members = %(    private static final Set<String> OPEN = Set.of("/api/open");\n)
    result = interceptor_guards(<<-JAVA, members)
            if (OPEN.contains(request.getRequestURI())) return true;
            if (request.getHeader("Authorization") == null) {
                response.setStatus(401);
                return false;
            }
            return true;
      JAVA
    result["GET /api/items"].should eq([GUARD])
    result["GET /api/open"].should be_empty
    result["GET /api/login"].should eq([GUARD])
  end

  it "does not read a helper refusal behind a pass-through it cannot read" do
    {
      "if (request.getRequestURI().startsWith(\"/api/o\")) {\n return true;\n }",
      "if (OpenPaths.computed().contains(request.getRequestURI())) {\n return true;\n }",
      "if (Dynamic.LIST.contains(request.getRequestURI())) return true;",
    }.each do |pass|
      extra = {"#{INTERCEPTOR_DIR}Dynamic.java" => "package com.example;\nclass Dynamic { static final List<String> LIST = load(\"/api/open\"); }"}
      result = interceptor_guards("#{pass}\n if (!authService.check()) {\n return responseTransform(response, 401, \"x\");\n }\n return true;", RESPONSE_HELPER, extra)
      fail "guarded behind #{pass}" unless result["GET /api/items"].empty?
    end
  end

  it "keeps passing OPTIONS and non-controller handlers through" do
    result = interceptor_guards(<<-JAVA, RESPONSE_HELPER)
            if ("OPTIONS".equals(request.getMethod())) {
                return true;
            }
            if (!(handler instanceof HandlerMethod)) {
                return true;
            }
            if (!authService.check()) {
                return responseTransform(response, 401, "login");
            }
            return true;
      JAVA
    result["GET /api/items"].should eq([GUARD])
  end

  it "ignores helpers that set another status, or a status that is not their parameter" do
    {
      {"private void reply(HttpServletResponse response, int code) { response.setStatus(code); }", "reply(response, 429);"},
      {"private void reply(HttpServletResponse response, int code) { response.setStatus(200); }", "reply(response, 401);"},
      {"private void reply(HttpServletResponse response, int code) { log(code); }", "reply(response, 401);"},
    }.each do |helper, call|
      result = interceptor_guards("if (limited()) {\n #{call}\n return false;\n }\n return true;", "    #{helper}\n")
      fail "guarded by #{helper} / #{call}" unless result["GET /api/items"].empty?
    end
  end

  it "leaves the review's look-alike helper refusals unread" do
    {
      "token present only" => "String token = request.getHeader(\"Authorization\");\n if (token != null && !jwt.verify(token)) {\n return responseTransform(response, 401, \"bad\");\n }\n return true;",
      "hasText nested"     => "String token = request.getHeader(\"Authorization\");\n if (StringUtils.hasText(token)) {\n if (!jwt.verify(token)) {\n return responseTransform(response, 401, \"bad\");\n }\n }\n return true;",
      "expired then null"  => "String token = request.getHeader(\"Authorization\");\n if (jwt.isExpired(token)) {\n return responseTransform(response, 401, \"expired\");\n }\n if (token == null) {\n return true;\n }\n return true;",
      "options compound"   => "String token = request.getHeader(\"Authorization\");\n if (\"OPTIONS\".equals(request.getMethod()) || token == null) {\n return true;\n }\n if (!jwt.verify(token)) {\n return responseTransform(response, 401, \"bad\");\n }\n return true;",
      "options negated"    => "if (!\"OPTIONS\".equals(request.getMethod())) {\n return true;\n }\n if (!authService.check()) {\n return responseTransform(response, 401, \"x\");\n }\n return true;",
      "ternary"            => "String token = request.getHeader(\"Authorization\");\n return token == null ? true : responseTransform(response, 401, \"x\");",
      "else pass"          => "String token = request.getHeader(\"Authorization\");\n if (token != null) {\n if (!jwt.verify(token)) return responseTransform(response, 401, \"x\");\n } else {\n return true;\n }\n return true;",
    }.each do |name, pre_handle|
      result = interceptor_guards(pre_handle, RESPONSE_HELPER)
      fail "#{name} guarded: #{result["GET /api/items"]}" unless result["GET /api/items"].empty?
    end
  end

  it "matches a status helper by arity" do
    members = <<-JAVA
          private boolean fail(HttpServletResponse response, int status) {
              response.setStatus(status);
              return false;
          }
          private boolean fail(HttpServletResponse response, int code, String msg) throws IOException {
              response.setStatus(200);
              return false;
          }
      JAVA
    result = interceptor_guards("if (!authService.check()) { return fail(response, 401, \"login\"); }\n return true;", members)
    result["GET /api/items"].should be_empty
  end

  it "does not read a string, or a list filled at runtime, as an allow-list" do
    {
      %(    private static final String OPEN = "/api/login,/api/open,/api/items";\n),
      %(    private static final Set<String> OPEN = new HashSet<>(Set.of("/api/login"));\n    @PostConstruct\n    void init() { OPEN.addAll(extra); }\n),
    }.each do |field|
      result = interceptor_guards(<<-JAVA, field)
              if (OPEN.contains(request.getRequestURI())) { return true; }
              if (request.getHeader("Authorization") == null) {
                  response.setStatus(401);
                  return false;
              }
              return true;
        JAVA
      result["GET /api/login"].should eq([GUARD])
      result["GET /api/items"].should eq([GUARD])
    end
  end

  it "stays linear on many helpers and statements" do
    pre_handle = (0...4000).map { |i| "if (a#{i}) { helper#{i}(response, 200, \"x\"); }" }.join("\n") + "\nreturn true;"
    members = (0...4000).map { |i| "    private void helper#{i}(HttpServletResponse response, int code, String msg) { response.setStatus(code); }\n" }.join
    started = Time.instant
    result = interceptor_guards(pre_handle, members)
    (Time.instant - started).should be < 5.seconds
    result["GET /api/items"].should be_empty
  end
end
