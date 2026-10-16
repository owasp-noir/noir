package com.example;

import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;

@Controller("/fixture")
public class FixtureController {
    @Get("/data")
    public String data() {
        return "data";
    }
}
