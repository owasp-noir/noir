package com.example;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/gadgets")
public class GadgetController {
    @GetMapping("/list")
    public String list() {
        return "[]";
    }
}
