package com.example;

import io.micronaut.http.annotation.Get;

public interface BookApi {
    @Get("/from-b")
    String list();
}
