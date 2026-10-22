package com.acme.api

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

// A subproject configured from the root build file: it has no build file of
// its own, so only its `src/` marks the sibling `build/` as build output.
@RestController
@RequestMapping("/api")
class UserController {
    @GetMapping("/users")
    fun list(): List<String> = listOf()
}
