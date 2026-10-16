package com.example.tck;

import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;

public class SuiteTests {
    @Controller("/tck-suite")
    static class PingController {
        @Get("/ping")
        String ping() {
            return "pong";
        }
    }
}
