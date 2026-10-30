package com.ex;

import com.linecorp.armeria.server.Server;
import com.linecorp.armeria.server.auth.AuthService;

public class A {
    public static void main(String[] args) {
        // Case 1: commented-out decorator next to a public route
        Server s1 = Server.builder()
            .service("/c1/public", (ctx, req) -> HttpResponse.of("ok"))
            // .decorator(AuthService.newDecorator(authorizer))
            .build();

        // Case 2: login service whose class name contains AuthService
        Server s2 = Server.builder()
            .service("/c2/login", new AuthServiceImpl())
            .build();

        // Case 3: per-route decorator via route builder next to an open route
        Server s3 = Server.builder()
            .service("/c3/open", (ctx, req) -> HttpResponse.of("ok"))
            .route().path("/c3/admin").decorator(AuthService.newDecorator(authorizer)).build(adminSvc)
            .build();

        // Case 4: annotatedService-level decorator next to an open route
        Server s4 = Server.builder()
            .service("/c4/open", (ctx, req) -> HttpResponse.of("ok"))
            .annotatedService().pathPrefix("/c4admin").decorator(AuthService.newDecorator(authorizer)).build(new Admin())
            .build();
    }
}
