package com.example;

import io.micronaut.http.annotation.Controller;

@Controller("/b")
public class BookController implements BookApi {
    @Override
    public String list() {
        return "b";
    }
}
