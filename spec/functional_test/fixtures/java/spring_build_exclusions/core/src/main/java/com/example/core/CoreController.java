package com.example.core;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class CoreController {
    @GetMapping("/core-ping")
    public String ping() {
        return "ok";
    }
}
