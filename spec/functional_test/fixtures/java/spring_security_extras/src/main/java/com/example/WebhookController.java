package com.example;

import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/webhook")
public class WebhookController {

    @PostMapping("/github")
    public String github(@RequestBody String payload) {
        return "ok";
    }
}
