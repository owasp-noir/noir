package com.example;

import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/admin")
public class AdminController {

    @PostMapping("/users")
    public String create(@RequestBody String user) {
        return "created";
    }
}
