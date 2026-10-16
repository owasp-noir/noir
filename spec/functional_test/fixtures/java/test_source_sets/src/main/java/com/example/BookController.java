package com.example;

import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;
import io.micronaut.http.annotation.QueryValue;

@Controller("/books")
public class BookController {
    @Get("/list")
    public String list(@QueryValue("page") int page) {
        return "ok";
    }
}
