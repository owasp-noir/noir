package com.example;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;

// @RestController on the superclass: Spring finds it up the hierarchy.
@RequestMapping("/api/tools")
public class ToolResource extends AbstractResource {
    @GetMapping("/list")
    public String list() {
        return "[]";
    }
}
