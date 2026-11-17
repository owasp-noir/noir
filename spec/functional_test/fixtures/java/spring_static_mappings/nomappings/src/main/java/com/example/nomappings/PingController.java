package com.example.nomappings;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class PingController {
    @GetMapping("/nomappings/ping")
    public String ping() {
        return "pong";
    }
}
