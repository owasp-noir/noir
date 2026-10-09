package com.example.api;

import static io.quarkus.vertx.web.Route.HandlerType.FAILURE;

import io.quarkus.vertx.web.Body;
import io.quarkus.vertx.web.Header;
import io.quarkus.vertx.web.Param;
import io.quarkus.vertx.web.Route;
import io.quarkus.vertx.web.RouteBase;
import jakarta.enterprise.context.ApplicationScoped;

@ApplicationScoped
@RouteBase(path = "/reactive")
public class ReactiveRoutes {
    @Route(path = "/events/:eventId", methods = Route.HttpMethod.GET)
    public String event(@Param String eventId, @Header("X-Trace") String trace) {
        return eventId;
    }

    @Route(path = "/commands", methods = {Route.HttpMethod.POST, Route.HttpMethod.PUT})
    public String command(@Body String payload, @Param("dryRun") String dryRun) {
        return payload;
    }

    @Route(path = "/status")
    public String status() {
        return "ok";
    }

    @Route(path = "/health") // liveness probe (k8s)
    public String health(@Param("verbose") String verbose) {
        return "ok";
    }

    @Route(path = "/ready")
    // readiness probe
    public String ready() {
        return "ok";
    }

    // @Route(path = "/disabled")
    public String disabled() {
        return "no";
    }

    @Route(path = "/*", type = FAILURE)
    public void failure() {
    }

    @Route(path = "/qualified-failure", type = io.quarkus.vertx.web.Route.HandlerType.FAILURE)
    public void qualifiedFailure() {
    }
}
