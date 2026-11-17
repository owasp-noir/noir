package com.example.legacy;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;

// Spring 5 still maps a bean whose type carries @RequestMapping.
@RequestMapping("/v1/widgets")
public class WidgetResource {
    @GetMapping("/list")
    public String list() {
        return "[]";
    }
}
