package com.example.portal;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class PortalController {
    @GetMapping("/portal-ping")
    public String ping() {
        return "ok";
    }
}
