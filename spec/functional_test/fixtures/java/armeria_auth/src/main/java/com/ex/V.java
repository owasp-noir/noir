package com.ex;

import com.linecorp.armeria.server.Server;
import com.linecorp.armeria.server.auth.AuthService;
import com.linecorp.armeria.server.auth.HttpAuthService;

public class V {
    void vh() {
        Server s = Server.builder()
            .service("/v3/vh/pub", svc)
            .virtualHost("admin.example.com")
                .service("/v3/vh/admin", svc)
                .route().path("/v3/vh/routeopen").build(svc)
                .decorator(AuthService.newDecorator(authorizer))
                .and()
            .virtualHost("other.example.com")
                .service("/v3/vh/other", svc)
                .route().path("/v3/vh/inner").decorator(HttpAuthService.newDecorator(authorizer)).build(svc)
                .service("/v3/vh/other2", svc)
                .and()
            .service("/v3/vh/pub2", svc)
            .build();
    }

    void exact() {
        Server s = Server.builder()
            .service("/v3/admin", svc)
            .service("/v3/admin/open", svc)
            .service("/v3/p/x", svc)
            .service("/v3/pp", svc)
            .decorator("/v3/admin", AuthService.newDecorator(authorizer))
            .decorator("prefix:/v3/p", AuthService.builder().add(authorizer).newDecorator())
            .build();
    }

    void glob() {
        Server s = Server.builder()
            .service("/v3/g/a/b", svc)
            .service("/v3/x/y", svc)
            .service("/v3/e", svc)
            .decorator("glob:/v3/g/**", AuthService.newDecorator(authorizer))
            .decorator("/v3/x/*", AuthService.newDecorator(authorizer))
            .decorator("exact:/v3/e", AuthService.newDecorator(authorizer))
            .build();
    }

    void variable() {
        java.util.function.Function<? super HttpService, AuthService> authDecorator = AuthService.newDecorator(authorizer);
        Server s = Server.builder()
            .service("/v3/var/r", svc)
            .decorator(authDecorator)
            .build();
    }

    void strings() {
        Server s = Server.builder()
            .service("/v3/str/r", (ctx, req) -> HttpResponse.of("AuthService.newDecorator(x)"))
            .service("/v3/str/r2", svc)
            .build();
    }

    void generic() {
        Server s = Server.builder()
            .<ServerBuilder>service("/v3/gen/a", svc)
            .service("/v3/gen/b", svc)
            .decorator(AuthService.newDecorator(authorizer))
            .build();
    }
}
