package com.example.war;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class WarController {
    @GetMapping("/war-ping")
    public String ping() {
        return "ok";
    }
}
