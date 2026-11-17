package com.example.docs;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class DocsController {
    @GetMapping("/docs-ping")
    public String ping() {
        return "ok";
    }
}
