require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Write `files` (relative path => source) under a temp root and run
# JaxrsAuthTagger over `routes` ("METHOD /url" => {file, text on the route
# line}). Returns each route's auth descriptions.
def run_jaxrs_auth(files : Hash(String, String), routes : Hash(String, {String, String})) : Hash(String, Array(String))
  CodeLocator.instance.clear_all
  root = File.tempname("jaxrs_auth")
  files.each do |relative, source|
    path = File.join(root, relative)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, source)
    CodeLocator.instance.register_path(path)
  end
  options = create_test_options
  options["base"] = YAML::Any.new(root)
  lines = Hash(String, Array(String)).new
  endpoints = routes.map do |route, location|
    method, url = route.split(' ', 2)
    file, text = location
    line = (lines[file] ||= files[file].lines).index!(&.includes?(text)) + 1
    endpoint = Endpoint.new(url, method, [] of Param, Details.new(PathInfo.new(File.join(root, file), line)))
    endpoint.details.technology = "java_jaxrs"
    endpoint
  end
  JaxrsAuthTagger.new(options).perform(endpoints)
  FileUtils.rm_rf(root)
  routes.keys.zip(endpoints).to_h { |route, endpoint| {route, endpoint.tags.select(&.name.==("auth")).map(&.description)} }
end

JAXRS_DIR = "src/main/java/com/example/"

def jaxrs_resource(body : String, path : String = "/api") : String
  <<-JAVA
    package com.example;

    @Path("#{path}")
    public class ApiResource {
    #{body}
    }
    JAVA
end

def jaxrs_filter(name : String, body : String, head : String = "@Provider") : String
  <<-JAVA
    package com.example;

    import jakarta.ws.rs.container.ContainerRequestContext;
    import jakarta.ws.rs.container.ContainerRequestFilter;

    #{head}
    public class #{name} implements ContainerRequestFilter {
        @Context
        private ResourceInfo resourceInfo;

        @Override
        public void filter(ContainerRequestContext requestContext) {
    #{body}
        }
    }
    JAVA
end

# A traccar-style filter: authenticate, and refuse unless @PermitAll.
SECURITY_FILTER_BODY = <<-JAVA
  if (requestContext.getMethod().equals("OPTIONS")) {
      return;
  }
  SecurityContext securityContext = null;
  try {
      String authHeader = requestContext.getHeaderString("Authorization");
      if (authHeader != null) {
          LoginResult result = loginService.login(authHeader);
          if (result != null) {
              securityContext = new UserSecurityContext(result.getUser());
          }
      } else {
          securityContext = loginService.fromSession(request);
      }
  } catch (StorageException e) {
      throw new WebApplicationException(e);
  }
  if (securityContext != null) {
      requestContext.setSecurityContext(securityContext);
  } else {
      Method method = resourceInfo.getResourceMethod();
      if (!method.isAnnotationPresent(PermitAll.class)) {
          Response.ResponseBuilder builder = Response.status(Response.Status.UNAUTHORIZED);
          throw new WebApplicationException(builder.build());
      }
  }
  JAVA

SESSION_RESOURCE = jaxrs_resource(<<-JAVA, "session")
      @PermitAll
      @GET // open
      public User current() { return null; }

      @Path("{id}")
      @GET // guarded
      public User get(@PathParam("id") long id) { return null; }
  JAVA

describe "JaxrsAuthTagger" do
  it "guards the methods a registered filter refuses, not @PermitAll ones" do
    files = {
      "#{JAXRS_DIR}SecurityRequestFilter.java" => jaxrs_filter("SecurityRequestFilter", SECURITY_FILTER_BODY, ""),
      "#{JAXRS_DIR}Config.java"                => "class Config { ResourceConfig create() { config.registerClasses(JacksonFeature.class, SecurityRequestFilter.class); return config; } }",
      "#{JAXRS_DIR}ApiResource.java"           => SESSION_RESOURCE,
    }
    result = run_jaxrs_auth(files, {
      "GET /session"      => {"#{JAXRS_DIR}ApiResource.java", "// open"},
      "GET /session/{id}" => {"#{JAXRS_DIR}ApiResource.java", "// guarded"},
    })
    result["GET /session"].should be_empty
    result["GET /session/{id}"].should eq(["Protected by JAX-RS request filter SecurityRequestFilter (401)"])
  end

  it "reads the route line stacked under other annotations" do
    files = {
      "#{JAXRS_DIR}SecurityRequestFilter.java" => jaxrs_filter("SecurityRequestFilter", SECURITY_FILTER_BODY),
      "#{JAXRS_DIR}ApiResource.java"           => jaxrs_resource(<<-JAVA),
          @GET // root
          @Operation(
                  summary = "Open (really)",
                  description = "<p>see @Docs</p>")
          @PermitAll
          public Response open() { return null; }

          @Operation(summary = "x")
          @GET
          @Path("/below")
          @ApiResponses(value = {
                  @ApiResponse(
                          responseCode = "200",
                          description = "A token",
                          content = @Content(schema = @Schema(type = "string"))),
                  @ApiResponse(responseCode = "400", description = "Bad request"),
                  @ApiResponse(responseCode = "401", description = "Unauthorized"),
                  @ApiResponse(responseCode = "403", description = "Forbidden"),
                  @ApiResponse(responseCode = "404", description = "Not found"),
                  @ApiResponse(responseCode = "409", description = "Conflict"),
                  @ApiResponse(responseCode = "500", description = "Server error"),
                  @ApiResponse(responseCode = "503", description = "Unavailable")
          })
          @Produces(MediaType.TEXT_PLAIN)
          @PermitAll
          public Response below() { return null; }

          @GET
          @Path("/closed")
          public Response closed() { return null; }
        JAVA
    }
    result = run_jaxrs_auth(files, {
      "GET /api"        => {"#{JAXRS_DIR}ApiResource.java", "@GET // root"},
      "GET /api/below"  => {"#{JAXRS_DIR}ApiResource.java", "@Path(\"/below\")"},
      "GET /api/closed" => {"#{JAXRS_DIR}ApiResource.java", "@Path(\"/closed\")"},
    })
    result["GET /api"].should be_empty
    result["GET /api/below"].should be_empty
    result["GET /api/closed"].size.should eq(1)
  end

  it "follows a DynamicFeature that registers the filter unless annotated" do
    filter = jaxrs_filter("AuthenticationFilter", <<-JAVA, "@Priority(Priorities.AUTHENTICATION)")
          if (requestContext instanceof final ContainerRequest request) {
              if (HttpMethod.OPTIONS.equals(request.getMethod())) {
                  return;
              }
              Principal principal = null;
              final var apiKey = new ApiKeyService(request);
              if (apiKey.isSpecified()) {
                  try {
                      principal = apiKey.authenticate();
                  } catch (AuthenticationException e) {
                      throw new NotAuthorizedException(Response.status(Response.Status.UNAUTHORIZED).build(), e);
                  }
              }
              if (principal == null) {
                  throw new NotAuthorizedException(Response.status(Response.Status.UNAUTHORIZED).build());
              }
          }
      JAVA
    feature = <<-JAVA
      @Provider
      public final class AuthFeature implements DynamicFeature {
          @Override
          public void configure(ResourceInfo resourceInfo, FeatureContext context) {
              if (!resourceInfo.getResourceMethod().isAnnotationPresent(AuthenticationNotRequired.class)) {
                  context.register(AuthenticationFilter.class);
              }
          }
      }
      JAVA
    files = {
      "#{JAXRS_DIR}AuthenticationFilter.java" => filter,
      "#{JAXRS_DIR}AuthFeature.java"          => feature,
      "#{JAXRS_DIR}ApiResource.java"          => jaxrs_resource(<<-JAVA),
          @GET // root
          @AuthenticationNotRequired
          public Response version() { return null; }

          @GET
          @Path("/projects")
          @PermissionRequired(Permissions.VIEW)
          public Response projects() { return null; }
        JAVA
    }
    result = run_jaxrs_auth(files, {
      "GET /api"          => {"#{JAXRS_DIR}ApiResource.java", "@GET // root"},
      "GET /api/projects" => {"#{JAXRS_DIR}ApiResource.java", "@Path(\"/projects\")"},
    })
    result["GET /api"].should be_empty
    result["GET /api/projects"].should eq(["Protected by JAX-RS request filter AuthenticationFilter (401)"])
  end

  it "leaves filters it cannot read, or that do not refuse a missing credential" do
    filters = {
      # never registered
      "Unregistered" => {"", "Principal p = null;\n if (p == null) { throw new NotAuthorizedException(\"no\"); }"},
      # a path whitelist returns first
      "Whitelist" => {"@Provider", "if (requestContext.getUriInfo().getPath().startsWith(\"public\")) {\n return;\n }\n Principal p = null;\n p = auth(requestContext);\n if (p == null) {\n throw new NotAuthorizedException(\"no\");\n }"},
      # a fallback credential: the refusal never fires
      "Fallback" => {"@Provider", "String token = requestContext.getHeaderString(\"Authorization\");\n if (token == null) token = defaults.token();\n if (token == null) throw new NotAuthorizedException(\"no\");"},
      # a constant fallback assigned unconditionally
      "Constant" => {"@Provider", "Principal p = null;\n p = ANONYMOUS;\n if (p == null) { throw new NotAuthorizedException(\"no\"); }"},
      # not a credential header
      "Origin" => {"@Provider", "String origin = requestContext.getHeaderString(\"Origin\");\n if (origin == null) {\n requestContext.abortWith(Response.status(403).build());\n }"},
      # refuses only an invalid credential, in a catch
      "Invalid" => {"@Provider", "try {\n check(requestContext.getHeaderString(\"Authorization\"));\n } catch (AuthException e) {\n throw new NotAuthorizedException(\"bad\");\n }"},
      # a wrapper exception with no status
      "Wrapper" => {"@Provider", "Principal p = null;\n p = auth(requestContext);\n if (p == null) { throw new WebApplicationException(\"failed\"); }"},
      # the refusal runs in a lambda
      "Lambda" => {"@Provider", "Principal p = null;\n p = auth(requestContext);\n checks.forEach(c -> { if (p == null) { throw new NotAuthorizedException(\"no\"); } });"},
      # refusal text in a comment and a string
      "Comment" => {"@Provider", "// if (p == null) throw new NotAuthorizedException(\"no\");\n log(\"if (p == null) { throw new NotAuthorizedException(x); }\");"},
      # a refusal limited to one kind of principal
      "Kind" => {"@Provider", "Principal p = null;\n p = auth(requestContext);\n if (p instanceof ApiKeyPrincipal) {\n if (p == null) { throw new NotAuthorizedException(\"no\"); }\n }"},
      # a refusal only when a setting is on
      "Setting" => {"@Provider", "Principal p = null;\n p = auth(requestContext);\n if (config.isAuthEnabled() && p == null) {\n throw new NotAuthorizedException(\"no\");\n }"},
      # an unbraced else-if that lets some callers through
      "Unbraced" => {"@Provider", "Principal p = null;\n p = auth(requestContext);\n if (p != null) requestContext.setSecurityContext(ctx(p)); else if (open(requestContext)) return;\n throw new NotAuthorizedException(\"no\");"},
      # a CSRF filter
      "CsrfGuard" => {"@Provider", "String token = requestContext.getHeaderString(\"X-Csrf-Token\");\n if (token == null) { throw new ForbiddenException(\"csrf\"); }"},
    }
    filters.each do |name, (head, body)|
      files = {
        "#{JAXRS_DIR}#{name}Filter.java" => jaxrs_filter("#{name}Filter", body, head),
        "#{JAXRS_DIR}ApiResource.java"   => jaxrs_resource("    @GET\n    public Response x() { return null; }"),
      }
      result = run_jaxrs_auth(files, {"GET /api" => {"#{JAXRS_DIR}ApiResource.java", "@GET"}})
      fail "#{name} guarded GET /api: #{result["GET /api"]}" unless result["GET /api"].empty?
    end
  end

  it "reads unbraced refusals, credential headers and abortWith" do
    {
      "if (requestContext.getHeaderString(\"Authorization\") == null)\n throw new NotAuthorizedException(\"no\");",
      "if (requestContext.getHeaderString(HttpHeaders.AUTHORIZATION) == null) {\n requestContext.abortWith(Response.status(Response.Status.UNAUTHORIZED).build());\n }",
      "Principal principal = null;\n principal = auth(requestContext);\n if (principal == null && !resourceInfo.getResourceMethod().isAnnotationPresent(PermitAll.class)) {\n throw new NotAuthorizedException(\"no\");\n }",
    }.each do |body|
      files = {
        "#{JAXRS_DIR}AuthFilter.java"  => jaxrs_filter("AuthFilter", body),
        "#{JAXRS_DIR}ApiResource.java" => jaxrs_resource("    @GET\n    public Response x() { return null; }"),
      }
      result = run_jaxrs_auth(files, {"GET /api" => {"#{JAXRS_DIR}ApiResource.java", "@GET"}})
      fail "not guarded: #{body}" unless result["GET /api"].size == 1
    end
  end

  it "reads a Kotlin filter" do
    filter = <<-KOTLIN
      @Provider
      class AuthFilter : ContainerRequestFilter {
          override fun filter(ctx: ContainerRequestContext) {
              if (ctx.method == "OPTIONS") return
              val principal: Principal? = null
              if (principal == null) {
                  throw NotAuthorizedException("no")
              }
          }
      }
      KOTLIN
    files = {
      "#{JAXRS_DIR}AuthFilter.kt"    => filter,
      "#{JAXRS_DIR}ApiResource.java" => jaxrs_resource("    @GET\n    public Response x() { return null; }"),
    }
    run_jaxrs_auth(files, {"GET /api" => {"#{JAXRS_DIR}ApiResource.java", "@GET"}})["GET /api"].size.should eq(1)
  end

  it "leaves the review's look-alike filters unread" do
    {
      # an allow-list read through a call result
      "allow-list" => "String open = PUBLIC.get(requestContext.getUriInfo().getPath());\n if (open != null) {\n return;\n }\n if (requestContext.getSecurityContext().getUserPrincipal() == null) {\n throw new NotAuthorizedException(\"login\");\n }",
      # an exemption read through a local
      "annotation local" => "PermitAll permit = resourceInfo.getResourceMethod().getAnnotation(PermitAll.class);\n if (permit == null && requestContext.getSecurityContext().getUserPrincipal() == null) {\n throw new NotAuthorizedException(\"login\");\n }",
      # a tenant lookup refusing 403
      "tenant" => "Tenant tenant = tenants.byHost(requestContext.getUriInfo().getBaseUri().getHost());\n if (tenant == null) {\n throw new ForbiddenException(\"unknown tenant\");\n }",
      # a 429 whose message says FORBIDDEN
      "quota" => "String bucket = null;\n bucket = Buckets.take(requestContext.getUriInfo().getPath());\n if (bucket == null) {\n throw new WebApplicationException(\"FORBIDDEN: UNAUTHORIZED 401\", 429);\n }",
      # a refusal a broad catch swallows
      "swallowed" => "try {\n if (requestContext.getSecurityContext().getUserPrincipal() == null) {\n throw new NotAuthorizedException(\"login\");\n }\n } catch (Exception e) {\n log(e);\n }",
      # refuses only a malformed credential
      "malformed" => "String auth = requestContext.getHeaderString(\"Authorization\");\n if (auth != null && !auth.startsWith(\"Bearer \")) {\n throw new NotAuthorizedException(\"bad\");\n }",
      # a path-limited refusal
      "path" => "String path = requestContext.getUriInfo().getPath();\n if (path.startsWith(\"admin\") && requestContext.getSecurityContext().getUserPrincipal() == null) {\n throw new NotAuthorizedException(\"bad\");\n }",
      # a method-limited refusal
      "method" => "if (!\"GET\".equals(requestContext.getMethod()) && requestContext.getSecurityContext().getUserPrincipal() == null) {\n throw new NotAuthorizedException(\"bad\");\n }",
      # GET requests pass first
      "get pass" => "if (\"GET\".equals(requestContext.getMethod())) {\n return;\n }\n if (requestContext.getSecurityContext().getUserPrincipal() == null) {\n throw new NotAuthorizedException(\"bad\");\n }",
      # only preflights are refused
      "preflight" => "if (!\"OPTIONS\".equals(requestContext.getMethod())) {\n return;\n }\n if (requestContext.getHeaderString(\"Authorization\") == null) {\n throw new NotAuthorizedException(\"x\");\n }",
      # a ternary guest fallback
      "ternary" => "Principal p = null;\n p = requestContext.getSecurityContext().getUserPrincipal();\n p = p != null ? p : Guest.create();\n if (p == null) {\n throw new NotAuthorizedException(\"bad\");\n }",
      # a fallback under its own absence test
      "fallback" => "String token = null;\n token = requestContext.getHeaderString(\"Authorization\");\n if (token == null) { token = defaults.token(); }\n if (token == null) throw new NotAuthorizedException(\"no\");",
      # a 403 on a missing principal (authorization, not authentication)
      "forbidden" => "if (!(requestContext.getSecurityContext().getUserPrincipal() instanceof final Principal principal)) {\n throw new ForbiddenException(Response.status(Response.Status.FORBIDDEN).build());\n }",
      # an else-if chain
      "else if" => "Principal p = null;\n p = auth(requestContext);\n if (p != null) {\n requestContext.setSecurityContext(ctx(p));\n } else if (open(requestContext)) {\n log();\n } else {\n throw new NotAuthorizedException(\"no\");\n }",
      # a credential-present early return
      "present return" => "Principal p = null;\n p = auth(requestContext);\n if (p != null) {\n return;\n }\n throw new NotAuthorizedException(\"no\");",
    }.each do |name, body|
      files = {
        "#{JAXRS_DIR}AuthFilter.java"  => jaxrs_filter("AuthFilter", body),
        "#{JAXRS_DIR}ApiResource.java" => jaxrs_resource("    @GET\n    public Response x() { return null; }"),
      }
      result = run_jaxrs_auth(files, {"GET /api" => {"#{JAXRS_DIR}ApiResource.java", "@GET"}})
      fail "#{name} guarded GET /api: #{result["GET /api"]}" unless result["GET /api"].empty?
    end
  end

  it "does not count registrations it cannot tie to the serving app" do
    filter = jaxrs_filter("AuthFilter", "if (requestContext.getSecurityContext().getUserPrincipal() == null) {\n throw new NotAuthorizedException(\"login\");\n }", "")
    resource = jaxrs_resource("    @GET\n    public Response x() { return null; }")
    {
      # a feature nobody registers
      "unregistered feature" => "public class AuthFeature implements DynamicFeature {\n public void configure(ResourceInfo resourceInfo, FeatureContext context) {\n if (!resourceInfo.getResourceMethod().isAnnotationPresent(PermitAll.class)) {\n context.register(AuthFilter.class);\n }\n }\n }",
      # a feature that reads the exemption through a local
      "feature local" => "@Provider\npublic class AuthFeature implements DynamicFeature {\n public void configure(ResourceInfo resourceInfo, FeatureContext context) {\n PermitAll permit = resourceInfo.getResourceMethod().getAnnotation(PermitAll.class);\n if (permit == null) {\n context.register(AuthFilter.class);\n }\n }\n }",
      # a setting decides
      "setting" => "public class App extends ResourceConfig {\n public App(Config config) {\n register(ApiResource.class);\n if (config.getBoolean(\"auth.enabled\")) {\n register(AuthFilter.class);\n }\n }\n }",
      # two applications, one registering the filter
      "two apps" => "public class Main {\n static ResourceConfig admin() {\n return new ResourceConfig().register(AdminResource.class).register(AuthFilter.class);\n }\n static ResourceConfig publicApi() {\n return new ResourceConfig().register(ApiResource.class);\n }\n }",
    }.each do |name, config|
      files = {
        "#{JAXRS_DIR}AuthFilter.java"  => filter,
        "#{JAXRS_DIR}Config.java"      => "package com.example;\n\nimport jakarta.ws.rs.core.Application;\n\n#{config}",
        "#{JAXRS_DIR}ApiResource.java" => resource,
      }
      result = run_jaxrs_auth(files, {"GET /api" => {"#{JAXRS_DIR}ApiResource.java", "@GET"}})
      fail "#{name} guarded GET /api: #{result["GET /api"]}" unless result["GET /api"].empty?
    end
  end

  it "binds a filter with an unknown annotation, and stops at one-line declarations" do
    files = {
      "#{JAXRS_DIR}AuthFilter.java"  => jaxrs_filter("AuthFilter", "if (requestContext.getSecurityContext().getUserPrincipal() == null) {\n throw new NotAuthorizedException(\"login\");\n }", "@Authn\n@Provider"),
      "#{JAXRS_DIR}ApiResource.java" => jaxrs_resource(<<-JAVA),
          @Authn @GET @Path("/a") public String a() { return ""; }
          @GET @Path("/b") public String b() { return ""; }
          @GET
          @Path("/c")
          public String c() { return ""; }
        JAVA
    }
    result = run_jaxrs_auth(files, {
      "GET /api/a" => {"#{JAXRS_DIR}ApiResource.java", "@Path(\"/a\")"},
      "GET /api/b" => {"#{JAXRS_DIR}ApiResource.java", "@Path(\"/b\")"},
      "GET /api/c" => {"#{JAXRS_DIR}ApiResource.java", "@Path(\"/c\")"},
    })
    result["GET /api/a"].size.should eq(1)
    result["GET /api/b"].should be_empty
    result["GET /api/c"].should be_empty
  end

  it "stays linear on many early returns and many endpoints" do
    body = (["if (\"OPTIONS\".equals(requestContext.getMethod())) { return; }"] * 4000).join("\n") +
           "\nif (requestContext.getSecurityContext().getUserPrincipal() == null) { throw new NotAuthorizedException(\"x\"); }"
    methods = (0...4000).map { |i| "    @GET\n    @Path(\"/e#{i}\")\n    public String e#{i}() { return \"\"; }\n" }.join
    files = {
      "#{JAXRS_DIR}AuthFilter.java"  => jaxrs_filter("AuthFilter", body),
      "#{JAXRS_DIR}ApiResource.java" => jaxrs_resource(methods),
    }
    routes = (0...4000).to_h { |i| {"GET /api/e#{i}", {"#{JAXRS_DIR}ApiResource.java", "@Path(\"/e#{i}\")"}} }
    started = Time.instant
    result = run_jaxrs_auth(files, routes)
    (Time.instant - started).should be < 5.seconds
    result["GET /api/e3999"].size.should eq(1)
  end

  it "limits a @NameBinding filter to the resources carrying its annotation" do
    files = {
      "#{JAXRS_DIR}Secured.java"       => "@NameBinding\n@Retention(RUNTIME)\n@Target({TYPE, METHOD})\npublic @interface Secured {}",
      "#{JAXRS_DIR}SecuredFilter.java" => jaxrs_filter("SecuredFilter", "Principal p = null;\n p = auth(requestContext);\n if (p == null) { requestContext.abortWith(Response.status(401).build()); }", "@Secured\n@Provider"),
      "#{JAXRS_DIR}ApiResource.java"   => jaxrs_resource(<<-JAVA),
          @GET // root
          public Response open() { return null; }

          @Secured
          @GET
          @Path("/admin")
          public Response admin() { return null; }
        JAVA
    }
    result = run_jaxrs_auth(files, {
      "GET /api"       => {"#{JAXRS_DIR}ApiResource.java", "@GET // root"},
      "GET /api/admin" => {"#{JAXRS_DIR}ApiResource.java", "@Path(\"/admin\")"},
    })
    result["GET /api"].should be_empty
    result["GET /api/admin"].should eq(["Protected by JAX-RS request filter SecuredFilter (401)"])
  end

  it "applies a filter only to the apps whose classpath holds its module" do
    pom = ->(artifact : String, dependency : String?) do
      deps = dependency ? "<dependencies><dependency><artifactId>#{dependency}</artifactId></dependency></dependencies>" : ""
      "<project><artifactId>#{artifact}</artifactId>#{deps}</project>"
    end
    files = {
      "lib/pom.xml"                        => pom.call("auth-lib", nil),
      "lib/#{JAXRS_DIR}AuthFilter.java"    => jaxrs_filter("AuthFilter", "if (requestContext.getHeaderString(\"Authorization\") == null) { throw new NotAuthorizedException(\"no\"); }"),
      "app/pom.xml"                        => pom.call("app", "auth-lib"),
      "app/#{JAXRS_DIR}ApiResource.java"   => jaxrs_resource("    @GET\n    public Response x() { return null; }"),
      "other/pom.xml"                      => pom.call("other", nil),
      "other/#{JAXRS_DIR}ApiResource.java" => jaxrs_resource("    @GET\n    public Response x() { return null; }", "/other"),
    }
    result = run_jaxrs_auth(files, {
      "GET /api"   => {"app/#{JAXRS_DIR}ApiResource.java", "@GET"},
      "GET /other" => {"other/#{JAXRS_DIR}ApiResource.java", "@GET"},
    })
    result["GET /api"].size.should eq(1)
    result["GET /other"].should be_empty
  end

  it "does not take another module's filter of the same name as the registered one" do
    files = {
      "lib/pom.xml"                      => "<project><artifactId>auth-lib</artifactId></project>",
      "lib/#{JAXRS_DIR}AuthFilter.java"  => jaxrs_filter("AuthFilter", "if (requestContext.getHeaderString(\"Authorization\") == null) { throw new NotAuthorizedException(\"no\"); }", ""),
      "app/pom.xml"                      => "<project><artifactId>app</artifactId></project>",
      "app/#{JAXRS_DIR}AuthFilter.java"  => jaxrs_filter("AuthFilter", "requestContext.setProperty(\"seen\", true);", ""),
      "app/#{JAXRS_DIR}Config.java"      => "class Config { void init() { config.register(AuthFilter.class); } }",
      "app/#{JAXRS_DIR}ApiResource.java" => jaxrs_resource("    @GET\n    public Response x() { return null; }"),
    }
    result = run_jaxrs_auth(files, {"GET /api" => {"app/#{JAXRS_DIR}ApiResource.java", "@GET"}})
    result["GET /api"].should be_empty
  end
end
