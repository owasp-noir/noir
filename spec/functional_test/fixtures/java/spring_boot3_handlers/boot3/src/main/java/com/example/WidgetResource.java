package com.example;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;

// Spring 6 maps only @Controller beans; a type-level @RequestMapping alone
// no longer makes this a handler.
//@RestController
@RequestMapping("/api/widgets")
public class WidgetResource {
    @GetMapping("/list")
    public String list(String color) {
        return "[]";
    }
}
