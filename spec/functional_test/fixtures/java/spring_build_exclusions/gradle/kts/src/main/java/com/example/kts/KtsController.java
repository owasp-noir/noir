package com.example.kts;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class KtsController {
    @GetMapping("/kts-ping")
    public String ping() {
        return "ok";
    }
}
