package com.example.api;

import static io.quarkus.vertx.web.Route.HttpMethod.POST;

import io.quarkus.vertx.web.Body;
import io.quarkus.vertx.web.Param;
import io.quarkus.vertx.web.Route;
import io.quarkus.vertx.web.RouteBase;

@RouteBase(path = "/reactive")
public class ReactiveRoutes {
    private final ReactiveService service = new ReactiveService();

    @Route(path = "/jobs/:jobId", methods = POST)
    public String submit(@Param String jobId, @Body String payload) {
        validate(jobId);
        java.util.function.Function<String, String> sanitizer = this::sanitize;
        String sanitized = sanitizer.apply(payload);
        service.submit(jobId, sanitized);
        AuditLog.write("reactive-submit");
        return sanitized;
    }

    @Route(path = "/profile")
    public String profile() {
        String profile = this.buildProfile();
        AuditLog.write(profile);
        return profile;
    }

    private void validate(String jobId) {}

    private String sanitize(String payload) {
        return payload.trim();
    }

    private String buildProfile() {
        return "profile";
    }

    private String overloaded(String raw) {
        wrongOverload(raw);
        return raw;
    }

    @Route(path = "/overloaded", methods = POST)
    public String overloaded() {
        return routeOverload();
    }

    private String routeOverload() {
        return "route";
    }

    private void wrongOverload(String raw) {}
}

class ReactiveService {
    void submit(String jobId, String payload) {}
}
