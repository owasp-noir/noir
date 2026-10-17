package com.example;

import org.springframework.web.bind.annotation.*;

@RestController
public class RootController {
    @RequestMapping("/")
    public String ping() { return "pong"; }
}
