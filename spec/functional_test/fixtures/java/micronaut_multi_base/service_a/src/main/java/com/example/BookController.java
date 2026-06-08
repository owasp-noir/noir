package com.example;

import io.micronaut.http.annotation.Controller;

@Controller("/a")
public class BookController implements BookApi {
    @Override
    public String list() {
        return "a";
    }
}
