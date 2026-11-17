package com.example.pattern;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class PingController {
    @GetMapping("/pattern/ping")
    public String ping() {
        return "pong";
    }
}
