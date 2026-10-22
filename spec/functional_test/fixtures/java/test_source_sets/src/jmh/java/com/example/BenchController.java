package com.example;

import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;

@Controller("/bench")
public class BenchController {
    @Get("/hello")
    public String hello() {
        return "hello";
    }
}
