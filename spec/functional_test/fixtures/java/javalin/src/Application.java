package com.example;

import io.javalin.Javalin;
import io.javalin.http.HttpMethod;
import io.javalin.http.HandlerType;
import io.javalin.http.staticfiles.Location;

import static io.javalin.apibuilder.ApiBuilder.*;

public class Application {
    private static final String API_PREFIX = "/api";
    private static final String REPORTS_PATH = "/reports";
    private static final String SOCKET_PATH = "/ws";
    private static final String TRACE_HEADER = "X-Report-Trace";

    static final class RouteParts {
        static final String DETAIL = "/{reportId}";
    }

    public static void main(String[] args) {
        Javalin app = Javalin.create(config -> {
            config.staticFiles.add("/public", Location.CLASSPATH);
            config.staticFiles.add(staticFiles -> {
                staticFiles.hostedPath = API_PREFIX + "/assets";
                staticFiles.directory = "/assets";
                staticFiles.location = Location.CLASSPATH;
            });
            config.staticFiles.enableWebjars();
        });

        app.get("/hello", ctx -> {
            String name = ctx.queryParam("name");
            ctx.result("Hello " + name);
        });

        app.post("/users", ctx -> {
            User user = ctx.bodyAsClass(User.class);
            ctx.json(user);
        });

        app.put("/users/{id}", ctx -> {
            String id = ctx.pathParam("id");
            User user = ctx.bodyAsClass(User.class);
            String trace = ctx.header("X-Trace");
            ctx.json(user);
        });

        app.routes(() -> {
            path("/api", () -> {
                get("/status", ctx -> ctx.result("ok"));
                path("/v1", () -> {
                    get("/health", ctx -> ctx.result("healthy"));
                    post("/submit", ctx -> {
                        Submission s = ctx.bodyAsClass(Submission.class);
                        String token = ctx.header("X-Token");
                        ctx.json(s);
                    });
                    get("/items/{itemId}", ctx -> {
                        String itemId = ctx.pathParam("itemId");
                        String category = ctx.queryParam("category");
                        ctx.result(itemId);
                    });
                });
            });
        });

        app.delete("/sessions/{id}", ctx -> {
            String id = ctx.pathParam("id");
            String session = ctx.cookie("session");
            ctx.status(204);
        });

        app.patch("/profile", ctx -> {
            String email = ctx.formParam("email");
            String phone = ctx.formParam("phone");
            ctx.result("ok");
        });

        app.post("/uploads/{uploadId}", ctx -> {
            String uploadId = ctx.pathParamAsClass("uploadId", String.class).get();
            ctx.uploadedFiles("files");
            ctx.formParams("tags");
            String batch = ctx.headerAsClass("X-Batch", String.class).get();
            ctx.queryParams("verbose");
            ctx.result(uploadId + batch);
        });

        app.post("/raw", ctx -> {
            ctx.bodyInputStream();
            ctx.status(202);
        });

        app.query("/search", ctx -> {
            ctx.bodyInputStream();
            String scope = ctx.queryParam("scope");
            ctx.result(scope);
        });

        app.sse("/stream/{streamId}", client -> {
            client.keepAlive();
        });

        app.addHttpHandler(HttpMethod.QUERY, "/advanced-search/{searchId}", ctx -> {
            String searchId = ctx.pathParam("searchId");
            String cursor = ctx.queryParam("cursor");
            ctx.result(searchId + cursor);
        });

        app.routes(() -> {
            path(API_PREFIX, () -> {
                get(REPORTS_PATH + RouteParts.DETAIL, ctx -> {
                    String reportId = ctx.pathParam("reportId");
                    String trace = ctx.header(TRACE_HEADER);
                    ctx.result(reportId);
                });
                crud("/projects/{projectId}", new ProjectController());
                ApiBuilder.path("/admin", () -> {
                    ApiBuilder.get("/audit/{auditId}", ctx -> {
                        String auditId = ctx.pathParam("auditId");
                        String expand = ctx.queryParam("expand");
                        ctx.result(auditId);
                    });
                });
                path("/teams/{teamId}", () -> {
                    get(ctx -> {
                        String filter = ctx.queryParam("filter");
                        ctx.result(filter);
                    });
                    put(ctx -> {
                        Team team = ctx.bodyAsClass(Team.class);
                        ctx.json(team);
                    });
                    delete(Application::deleteTeam);
                });
                path("/tasks/{taskId}", () -> {
                    crud(new TaskController());
                });
            });
        });

        app.addHandler(HandlerType.POST, "/imports/{importId}", ctx -> {
            ImportRequest request = ctx.bodyAsClass(ImportRequest.class);
            String importId = ctx.pathParam("importId");
            ctx.json(request);
        });

        app.post("/webhooks/{webhookId}", Application::handleWebhook);

        app.ws(API_PREFIX + SOCKET_PATH + "/{roomId}", ws -> {
            ws.onConnect(ctx -> {
                String roomId = ctx.pathParam("roomId");
                String token = ctx.queryParam("token");
                ctx.attribute("roomId", roomId);
            });
        });

        app.start(7000);
    }

    static class User {
        public String name;
        public String email;
    }

    static class Submission {
        public String content;
    }

    static class ImportRequest {
        public String source;
    }

    static class Team {
        public String name;
    }

    private static void deleteTeam(io.javalin.http.Context ctx) {
        ctx.status(204);
    }

    private static void handleWebhook(io.javalin.http.Context ctx) {
        WebhookPayload payload = ctx.bodyAsClass(WebhookPayload.class);
        String webhookId = ctx.pathParam("webhookId");
        String signature = ctx.header("X-Signature");
        String dryRun = ctx.queryParam("dryRun");
        ctx.json(payload);
    }

    static class ProjectController implements io.javalin.apibuilder.CrudHandler {
        public void getAll(io.javalin.http.Context ctx) {}
        public void getOne(io.javalin.http.Context ctx, String projectId) {}
        public void create(io.javalin.http.Context ctx) {}
        public void update(io.javalin.http.Context ctx, String projectId) {}
        public void delete(io.javalin.http.Context ctx, String projectId) {}
    }

    static class TaskController implements io.javalin.apibuilder.CrudHandler {
        public void getAll(io.javalin.http.Context ctx) {}
        public void getOne(io.javalin.http.Context ctx, String taskId) {}
        public void create(io.javalin.http.Context ctx) {}
        public void update(io.javalin.http.Context ctx, String taskId) {}
        public void delete(io.javalin.http.Context ctx, String taskId) {}
    }

    static class WebhookPayload {
        public String event;
    }
}
