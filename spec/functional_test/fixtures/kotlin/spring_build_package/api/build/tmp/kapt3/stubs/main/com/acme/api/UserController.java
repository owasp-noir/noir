package com.acme.api;

import org.springframework.web.bind.annotation.*;

// Stale kapt stub: build output, must stay pruned.
@RestController
@RequestMapping(value = {"/api"})
public final class UserController {
    @GetMapping(value = {"/users"})
    public java.util.List<java.lang.String> list() { return null; }

    @PostMapping(value = {"/stale"})
    public void stale() { }
}
