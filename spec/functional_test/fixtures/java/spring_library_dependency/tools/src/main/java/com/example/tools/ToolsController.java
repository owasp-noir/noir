package com.example.tools;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ToolsController {
    @GetMapping("/ping")
    public String ping() {
        return "ok";
    }
}
