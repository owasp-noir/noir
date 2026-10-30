package com.example;

import com.linecorp.armeria.common.HttpResponse;
import com.linecorp.armeria.server.Server;
import com.linecorp.armeria.server.auth.AuthService;
import com.linecorp.armeria.server.auth.Authorizer;

public class ApiServer {
    public static void main(String[] args) {
        Authorizer<com.linecorp.armeria.common.HttpRequest> authorizer = (ctx, req) -> null;
        Server server = Server.builder()
            .http(8080)
            .service("/welcome", (ctx, req) -> HttpResponse.of("ok"))
            .service("/inline", svc.decorate(AuthService.newDecorator(authorizer)))
            .service("/other", (ctx, req) -> HttpResponse.of("ok"))
            .service("/admin/users", (ctx, req) -> HttpResponse.of("users"))
            .decoratorUnder("/admin", AuthService.newDecorator(authorizer))
            .build();
        server.start().join();
    }
}
