package com.example;

import org.springframework.web.bind.annotation.*;

@RestController
public class QuoteController {
    @GetMapping("/v1/quote")
    public String quote(@RequestParam("sym") String sym) { return sym; }
}
