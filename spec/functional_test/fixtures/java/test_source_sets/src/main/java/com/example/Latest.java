package com.example;

import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;

// A real controller whose name merely ends in "est.java" must survive the
// case-sensitive `*Test.java` basename gate.
@Controller("/latest")
public class Latest {
    @Get("/news")
    public String news() {
        return "ok";
    }
}
