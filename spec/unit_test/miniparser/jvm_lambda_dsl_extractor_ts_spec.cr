require "spec"
require "../../../src/models/logger"
require "../../../src/miniparsers/jvm_lambda_dsl_extractor_ts"

describe Noir::TreeSitterJvmLambdaDslExtractor do
  config = Noir::TreeSitterJvmLambdaDslExtractor::Config.new(
    verb_methods: {
      "get"   => "GET",
      "post"  => "POST",
      "put"   => "PUT",
      "query" => "QUERY",
      "sse"   => "GET",
    },
    nest_methods: Set{"path"},
    handler_methods: Set{"addHandler", "addHttpHandler"},
    crud_methods: Set{"crud"},
    query_methods: Set{"queryParam", "queryParams"},
    form_methods: Set{"formParam", "formParams", "uploadedFiles"},
    header_methods: Set{"header", "headerAsClass"},
    body_methods: Set{"bodyInputStream"},
    body_typed_methods: Set{"bodyAsClass"}
  )

  websocket_config = Noir::TreeSitterJvmLambdaDslExtractor::Config.new(
    verb_methods: {
      "get" => "GET",
    },
    nest_methods: Set{"path"},
    websocket_methods: Set{"ws"},
    query_methods: Set{"queryParam"}
  )

  spark_config = Noir::TreeSitterJvmLambdaDslExtractor::Config.new(
    verb_methods: {
      "get"  => "GET",
      "post" => "POST",
      "any"  => "ANY",
    },
    nest_methods: Set{"path"},
    router_receivers: Set{"redirect"}
  )

  it "resolves constants and concatenations in paths and handler params" do
    source = <<-JAVA
      package com.example;

      import io.javalin.Javalin;
      import static io.javalin.apibuilder.ApiBuilder.*;

      public class Application {
          private static final String API_PREFIX = "/api";
          private static final String TRACE_HEADER = "X-Trace";

          static final class Routes {
              static final String USERS = "/users";
              static final String DETAIL = "/{id}";
          }

          void register(Javalin app) {
              app.routes(() -> {
                  path(API_PREFIX, () -> {
                      get(Routes.USERS + Routes.DETAIL, ctx -> {
                          String expand = ctx.queryParam("expand");
                          String trace = ctx.header(TRACE_HEADER);
                      });
                  });
              });
          }
      }
      JAVA

    routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, config)
    routes.map { |r| {r.verb, r.path, r.query_params, r.header_params} }.should eq([
      {"GET", "/api/users/{id}", ["expand"], ["X-Trace"]},
    ])
  end

  it "expands Javalin CrudHandler registrations" do
    source = <<-JAVA
      package com.example;

      import io.javalin.Javalin;
      import static io.javalin.apibuilder.ApiBuilder.*;

      public class Application {
          private static final String API = "/api";
          private static final String PROJECTS = "/projects/{projectId}";

          void register(Javalin app) {
              app.routes(() -> {
                  path(API, () -> {
                      crud(PROJECTS, new ProjectController());
                  });
              });
          }
      }
      JAVA

    routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, config)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/api/projects"},
      {"POST", "/api/projects"},
      {"GET", "/api/projects/{projectId}"},
      {"PATCH", "/api/projects/{projectId}"},
      {"DELETE", "/api/projects/{projectId}"},
    ])
  end

  it "uses the current path prefix for pathless Javalin CrudHandler registrations" do
    source = <<-JAVA
      package com.example;

      import io.javalin.Javalin;
      import static io.javalin.apibuilder.ApiBuilder.*;

      public class Application {
          void register(Javalin app) {
              app.routes(() -> {
                  path("/api/tasks/{taskId}", () -> {
                      crud(new TaskController());
                  });
              });
          }
      }
      JAVA

    routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, config)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/api/tasks"},
      {"POST", "/api/tasks"},
      {"GET", "/api/tasks/{taskId}"},
      {"PATCH", "/api/tasks/{taskId}"},
      {"DELETE", "/api/tasks/{taskId}"},
    ])
  end

  it "extracts Javalin addHandler registrations with HandlerType enums" do
    source = <<-JAVA
      package com.example;

      import io.javalin.Javalin;
      import io.javalin.http.HandlerType;

      public class Application {
          void register(Javalin app) {
              app.addHandler(HandlerType.POST, "/imports/{importId}", ctx -> {
                  ImportRequest request = ctx.bodyAsClass(ImportRequest.class);
                  String expand = ctx.queryParam("expand");
              });
          }
      }
      JAVA

    routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, config)
    routes.map { |r| {r.verb, r.path, r.query_params, r.body_type} }.should eq([
      {"POST", "/imports/{importId}", ["expand"], "ImportRequest"},
    ])
  end

  it "extracts Javalin WebSocket routes with ws protocol" do
    source = <<-JAVA
      package com.example;

      import io.javalin.Javalin;

      public class Application {
          private static final String API = "/api";
          private static final String SOCKET = "/ws";

          void register(Javalin app) {
              app.ws(API + SOCKET + "/{roomId}", ws -> {
                  ws.onConnect(ctx -> {
                      String token = ctx.queryParam("token");
                  });
              });
          }
      }
      JAVA

    routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, websocket_config)
    routes.map { |r| {r.verb, r.path, r.protocol, r.query_params} }.should eq([
      {"GET", "/api/ws/{roomId}", "ws", ["token"]},
    ])
  end

  it "uses the current path prefix for Javalin pathless ApiBuilder verb calls" do
    source = <<-JAVA
      package com.example;

      import io.javalin.Javalin;
      import static io.javalin.apibuilder.ApiBuilder.*;

      public class Application {
          void register(Javalin app) {
              app.routes(() -> {
                  path("/api", () -> {
                      path("/teams/{teamId}", () -> {
                          get(ctx -> {
                              String filter = ctx.queryParam("filter");
                          });
                          put(Application::updateTeam);
                      });
                  });
              });
          }
      }
      JAVA

    routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, config)
    routes.map { |r| {r.verb, r.path, r.query_params} }.should eq([
      {"GET", "/api/teams/{teamId}", ["filter"]},
      {"PUT", "/api/teams/{teamId}", [] of String},
    ])
  end

  it "scans same-file method reference handler bodies" do
    source = <<-JAVA
      package com.example;

      import io.javalin.Javalin;

      public class Application {
          void register(Javalin app) {
              app.post("/imports/{importId}", Application::importData);
          }

          static void importData(Context ctx) {
              ImportRequest request = ctx.bodyAsClass(ImportRequest.class);
              String expand = ctx.queryParam("expand");
              String trace = ctx.header("X-Trace");
          }
      }
      JAVA

    routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, config)
    routes.map { |r| {r.verb, r.path, r.query_params, r.header_params, r.body_type} }.should eq([
      {"POST", "/imports/{importId}", ["expand"], ["X-Trace"], "ImportRequest"},
    ])
  end

  it "keeps scanning chained validator helper calls whose terminal method is named like a route verb" do
    source = <<-JAVA
      package com.example;

      import io.javalin.Javalin;

      public class Application {
          void register(Javalin app) {
              app.post("/uploads/{uploadId}", ctx -> {
                  String batch = ctx.headerAsClass("X-Batch", String.class).get();
                  ctx.queryParams("verbose");
                  ctx.uploadedFiles("files");
                  ctx.formParams("tags");
              });
              app.post("/raw", ctx -> {
                  ctx.bodyInputStream();
              });
          }
      }
      JAVA

    routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, config)
    routes.map { |r| {r.verb, r.path, r.query_params, r.form_params, r.header_params, r.has_body?} }.should eq([
      {"POST", "/uploads/{uploadId}", ["verbose"], ["files", "tags"], ["X-Batch"], false},
      {"POST", "/raw", [] of String, [] of String, [] of String, true},
    ])
  end

  it "extracts Javalin query, SSE, and addHttpHandler routes" do
    source = <<-JAVA
      package com.example;

      import io.javalin.Javalin;
      import io.javalin.http.HttpMethod;

      public class Application {
          void register(Javalin app) {
              app.query("/search", ctx -> {
                  String scope = ctx.queryParam("scope");
                  ctx.bodyInputStream();
              });
              app.sse("/stream/{streamId}", client -> {
                  client.keepAlive();
              });
              app.addHttpHandler(HttpMethod.QUERY, "/advanced-search/{searchId}", ctx -> {
                  String cursor = ctx.queryParam("cursor");
              });
          }
      }
      JAVA

    routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, config)
    routes.map { |r| {r.verb, r.path, r.query_params, r.has_body?} }.should eq([
      {"QUERY", "/search", ["scope"], true},
      {"GET", "/stream/{streamId}", [] of String, false},
      {"QUERY", "/advanced-search/{searchId}", ["cursor"], false},
    ])
  end

  it "extracts Spark redirect API routes without handler lambdas" do
    source = <<-JAVA
      package com.example;

      import static spark.Spark.*;

      public class Application {
          void register() {
              redirect.get("/legacy-home", "/hello");
              redirect.post("/legacy-submit", "/api/v1/submit", Redirect.Status.SEE_OTHER);
              redirect.any("/legacy-any", "/hello", Redirect.Status.MOVED_PERMANENTLY);
          }
      }
      JAVA

    routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, spark_config)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/legacy-home"},
      {"POST", "/legacy-submit"},
      {"ANY", "/legacy-any"},
    ])
  end

  it "ignores collection calls that collide with verb method names" do
    source = <<-JAVA
      package com.example;

      import static spark.Spark.*;
      import java.util.HashMap;
      import java.util.Map;

      public class Application {
          void register() {
              Map<String, String> credentials = new HashMap<>();
              String secret = credentials.get("admin");

              get("/users/:name", (req, res) -> "hi");
              post("/login", LoginHandler::handle);
          }
      }
      JAVA

    routes = Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(source, spark_config)
    # `credentials.get("admin")` reads like `get("/admin", ...)` by method
    # name alone — but its receiver is a Map and it carries no handler, so
    # it must not surface as a route.
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/users/:name"},
      {"POST", "/login"},
    ])
  end
end
