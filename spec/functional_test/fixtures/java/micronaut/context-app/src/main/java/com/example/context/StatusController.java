package com.example.context;

import io.micronaut.http.HttpResponse;
import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;

@Controller("/status")
public class StatusController {
    @Get
    public HttpResponse<?> get() {
        return HttpResponse.ok();
    }
}
