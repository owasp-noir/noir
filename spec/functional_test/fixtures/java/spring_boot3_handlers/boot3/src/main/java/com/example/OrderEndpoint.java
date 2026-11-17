package com.example;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;

@ApiController
@RequestMapping("/api/orders")
public class OrderEndpoint {
    @GetMapping("/list")
    public String list() {
        return "[]";
    }
}
