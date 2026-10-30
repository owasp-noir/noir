package com.ex;

import com.linecorp.armeria.server.Server;
import com.linecorp.armeria.server.auth.AuthService;

public class B {
    void two() {
        Server guarded = Server.builder()
            .service("/b/guarded", (ctx, req) -> HttpResponse.of("ok"))
            .decorator(AuthService.newDecorator(authorizer))
            .build();
        Server open = Server.builder()
            .service("/b/open", (ctx, req) -> HttpResponse.of("ok"))
            .build();
        Server scoped = Server.builder()
            .service("/b/scoped/admin", svc)
            .service("/b/scoped/public", svc)
            .decorator("prefix:/b/scoped/admin", AuthService.newDecorator(authorizer))
            .build();
    }
}
