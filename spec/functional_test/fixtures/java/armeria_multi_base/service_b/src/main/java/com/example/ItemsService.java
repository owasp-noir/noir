package com.example;

import com.linecorp.armeria.common.HttpResponse;
import com.linecorp.armeria.server.annotation.Get;

public class ItemsService {
    @Get("/b-only")
    public HttpResponse list() {
        return HttpResponse.of("b");
    }
}
