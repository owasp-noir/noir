package com.example.maven;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class MavenController {
    @GetMapping("/maven-ping")
    public String ping() {
        return "ok";
    }
}
