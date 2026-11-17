package com.example.mixed;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class PingController {
    @GetMapping("/mixed/ping")
    public String ping() {
        return "pong";
    }
}
