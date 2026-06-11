require "spec"
require "../../../src/models/logger"
require "../../../src/miniparsers/jaxrs_extractor_ts"

describe Noir::TreeSitterJaxRsExtractor do
  it "extracts application-level base paths from @ApplicationPath" do
    source = <<-JAVA
      package com.example;

      import jakarta.ws.rs.ApplicationPath;
      import jakarta.ws.rs.core.Application;

      public final class Paths {
          public static final String API = "/rest";
      }

      @ApplicationPath(Paths.API)
      public class RestApplication extends Application {
      }
      JAVA

    Noir::TreeSitterJaxRsExtractor.extract_application_path(source).should eq("/rest")
  end

  it "composes same-file sub-resource locator paths" do
    source = <<-JAVA
      package com.example.api;

      import jakarta.ws.rs.GET;
      import jakarta.ws.rs.POST;
      import jakarta.ws.rs.Path;
      import jakarta.ws.rs.PathParam;
      import jakarta.ws.rs.QueryParam;
      import jakarta.ws.rs.core.Response;

      @Path("/users")
      public class UserResource {
          @Path("/{id}")
          public UserItemResource item(@PathParam("id") String id) {
              return new UserItemResource();
          }
      }

      class UserItemResource {
          @GET
          public Response show(@QueryParam("expand") String expand) {
              return Response.ok().build();
          }

          @GET
          @Path("/settings")
          public Response settings() {
              return Response.ok().build();
          }

          @POST
          @Path("/orders")
          public Response createOrder() {
              return Response.ok().build();
          }
      }
      JAVA

    routes = Noir::TreeSitterJaxRsExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/users/{id}"},
      {"GET", "/users/{id}/settings"},
      {"POST", "/users/{id}/orders"},
    ])
    routes.map(&.path).should_not contain("/settings")
  end

  it "composes imported cross-file sub-resource locator paths" do
    root = <<-JAVA
      package com.example.api;

      import jakarta.ws.rs.Path;
      import jakarta.ws.rs.PathParam;

      @Path("/users")
      public class UserResource {
          @Path("/{id}/profile")
          public UserProfileResource profile(@PathParam("id") String id) {
              return new UserProfileResource();
          }
      }
      JAVA

    profile = <<-JAVA
      package com.example.api;

      import jakarta.ws.rs.GET;
      import jakarta.ws.rs.Path;
      import jakarta.ws.rs.QueryParam;
      import jakarta.ws.rs.core.Response;

      public class UserProfileResource {
          @GET
          public Response show(@QueryParam("include") String include) {
              return Response.ok().build();
          }

          @GET
          @Path("/settings")
          public Response settings() {
              return Response.ok().build();
          }
      }
      JAVA

    sources = {
      "UserProfileResource" => {"UserProfileResource.java", profile},
    } of String => Noir::TreeSitterJaxRsExtractor::SourceEntry

    routes = Noir::TreeSitterJaxRsExtractor.extract_routes(root, subresource_sources: sources)
    routes.map { |r| {r.verb, r.path, r.file_path} }.should eq([
      {"GET", "/users/{id}/profile", "UserProfileResource.java"},
      {"GET", "/users/{id}/profile/settings", "UserProfileResource.java"},
    ])
  end

  it "composes JAX-RS interface routes onto implementing resource classes" do
    source = <<-JAVA
      package com.example.api;

      import jakarta.ws.rs.GET;
      import jakarta.ws.rs.Path;
      import jakarta.ws.rs.PathParam;
      import jakarta.ws.rs.QueryParam;
      import jakarta.ws.rs.core.Response;

      @Path("/catalog")
      public interface CatalogApi {
          @GET
          @Path("/{id}")
          Response show(@PathParam("id") String id, @QueryParam("view") String view);
      }

      @Path("/api")
      public class CatalogResource implements CatalogApi {
          public Response show(String id, String view) {
              return Response.ok().build();
          }
      }
      JAVA

    routes = Noir::TreeSitterJaxRsExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.params} }.should eq([
      {"GET", "/api/catalog/{id}", [
        Param.new("view", "", "query"),
      ]},
    ])
    routes.map(&.path).should_not contain("/catalog/{id}")
  end

  it "resolves constants and concatenations in @Path annotations" do
    source = <<-JAVA
      package com.example.api;

      import jakarta.ws.rs.GET;
      import jakarta.ws.rs.Path;
      import jakarta.ws.rs.core.Response;

      public final class ApiPaths {
          public static final String API = "/api";
          public static final String USERS = API + "/users";
      }

      @Path(ApiPaths.USERS)
      public class ConstantPathResource {
          private static final String DETAIL = "/{id}";
          private static final String SETTINGS = DETAIL + "/settings";

          @GET
          @Path(SETTINGS)
          public Response settings() {
              return Response.ok().build();
          }
      }
      JAVA

    routes = Noir::TreeSitterJaxRsExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/api/users/{id}/settings"},
    ])
  end

  it "expands BeanParam fields and setters with default values" do
    source = <<-JAVA
      package com.example.api;

      import jakarta.ws.rs.BeanParam;
      import jakarta.ws.rs.DefaultValue;
      import jakarta.ws.rs.GET;
      import jakarta.ws.rs.HeaderParam;
      import jakarta.ws.rs.Path;
      import jakarta.ws.rs.QueryParam;
      import jakarta.ws.rs.core.Response;

      @Path("/users")
      public class UserResource {
          private static final String INCLUDE = "include";
          private static final String TRACE = "X-Trace";

          @GET
          public Response list(@BeanParam UserFilter filter) {
              return Response.ok().build();
          }

          @GET
          @Path("/{id}")
          public Response show(@PathParam("id") String id,
                               @QueryParam(INCLUDE) String include,
                               @HeaderParam(TRACE) String trace) {
              return Response.ok().build();
          }
      }

      class UserFilter {
          private static final String ACTIVE = "active";
          private static final String DEFAULT_ACTIVE = "false";
          private static final String TENANT = "X-Tenant";
          private static final String SORT = "sort";
          private static final String DEFAULT_SORT = "created";

          @QueryParam(ACTIVE)
          @DefaultValue(DEFAULT_ACTIVE)
          private Boolean active;

          private String sort;

          @HeaderParam(TENANT)
          private String tenant;

          @QueryParam(SORT)
          @DefaultValue(DEFAULT_SORT)
          public void setSort(String sort) {
              this.sort = sort;
          }
      }
      JAVA

    bean_index = Noir::TreeSitterJaxRsExtractor.extract_bean_fields(source)
    routes = Noir::TreeSitterJaxRsExtractor.extract_routes(source, bean_index: bean_index)
    routes.map { |r| {r.verb, r.path, r.params} }.should eq([
      {"GET", "/users", [
        Param.new("active", "false", "query"),
        Param.new("X-Tenant", "", "header"),
        Param.new("sort", "created", "query"),
      ]},
      {"GET", "/users/{id}", [
        Param.new("include", "", "query"),
        Param.new("X-Trace", "", "header"),
      ]},
    ])
  end

  it "skips injected context types without dropping explicit request params" do
    source = <<-JAVA
      package com.example.api;

      import io.quarkus.security.identity.SecurityIdentity;
      import io.smallrye.jwt.auth.principal.JsonWebToken;
      import io.vertx.ext.web.RoutingContext;
      import jakarta.ws.rs.POST;
      import jakarta.ws.rs.Path;
      import jakarta.ws.rs.container.AsyncResponse;
      import jakarta.ws.rs.container.Suspended;
      import jakarta.ws.rs.core.SecurityContext;
      import jakarta.ws.rs.core.Response;
      import org.jboss.resteasy.reactive.RestForm;

      @Path("/auth")
      public class LoginResource {
          @POST
          @Path("/login")
          public Response login(@RestForm String username,
                                RoutingContext ctx,
                                SecurityContext securityContext,
                                SecurityIdentity identity,
                                JsonWebToken token,
                                @Suspended AsyncResponse ar,
                                LoginPayload payload) {
              return Response.ok().build();
          }
      }

      class LoginPayload {
          public String otp;
      }
      JAVA

    dto_index = {
      "LoginPayload" => [
        Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("otp", "public", false, ""),
      ],
    }
    routes = Noir::TreeSitterJaxRsExtractor.extract_routes(source, dto_index: dto_index)
    routes.map { |r| {r.verb, r.path, r.params} }.should eq([
      {"POST", "/auth/login", [
        Param.new("username", "", "form"),
        Param.new("otp", "", "json"),
      ]},
    ])
  end

  it "extracts multipart form fields from MultipartFormDataInput usage" do
    source = <<-JAVA
      package com.example.api;

      import jakarta.ws.rs.Consumes;
      import jakarta.ws.rs.POST;
      import jakarta.ws.rs.Path;
      import jakarta.ws.rs.core.MediaType;
      import jakarta.ws.rs.core.Response;
      import org.jboss.resteasy.plugins.providers.multipart.MultipartFormDataInput;

      @Path("/images")
      public class ImageResource {
          @POST
          @Path("/watermark")
          @Consumes(MediaType.MULTIPART_FORM_DATA)
          public Response watermark(MultipartFormDataInput data) {
              data.getFormDataMap().get("image").get(0);
              data.getFormDataMap().get("metadata");
              return Response.accepted().build();
          }

          @POST
          @Path("/raw")
          @Consumes("multipart/form-data")
          public Response raw(MultipartFormDataInput data) {
              return Response.accepted().build();
          }
      }
      JAVA

    routes = Noir::TreeSitterJaxRsExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.params} }.should eq([
      {"POST", "/images/watermark", [
        Param.new("image", "", "form"),
        Param.new("metadata", "", "form"),
      ]},
      {"POST", "/images/raw", [
        Param.new("data", "", "form"),
      ]},
    ])
  end

  it "extracts Jakarta ServerEndpoint routes with ws protocol" do
    source = <<-JAVA
      package com.example.api;

      import jakarta.websocket.server.ServerEndpoint;

      @ServerEndpoint(ChatSocket.API + "/chat/{roomId}")
      public class ChatSocket {
          static final String API = "/ws";
      }
      JAVA

    routes = Noir::TreeSitterJaxRsExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.protocol} }.should eq([
      {"GET", "/ws/chat/{roomId}", "ws"},
    ])
  end
end
