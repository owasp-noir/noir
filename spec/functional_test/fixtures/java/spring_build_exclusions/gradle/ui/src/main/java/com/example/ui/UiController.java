package com.example.ui;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class UiController {
    @GetMapping("/ui-ping")
    public String ping() {
        return "ok";
    }
}
