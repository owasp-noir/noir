package com.example;

import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/public")
public class OpenController {

    @GetMapping("/health")
    public String health() {
        return "ok";
    }

    @GetMapping("/info")
    public String info() {
        return "info";
    }
}
