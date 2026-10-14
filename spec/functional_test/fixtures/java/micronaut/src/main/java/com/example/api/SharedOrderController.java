package com.example.api;

import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;

@Controller(SharedPaths.ORDERS)
public class SharedOrderController {
    @Get("/{id}")
    public String get(String id) { return ""; }
}
