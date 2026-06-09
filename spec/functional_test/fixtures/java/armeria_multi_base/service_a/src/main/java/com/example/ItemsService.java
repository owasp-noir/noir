package com.example;

import com.linecorp.armeria.common.HttpResponse;
import com.linecorp.armeria.server.annotation.Get;

public class ItemsService {
    @Get("/a-only")
    public HttpResponse list() {
        return HttpResponse.of("a");
    }
}
