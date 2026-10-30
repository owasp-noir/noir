package com.acme.zoo.web.api

import org.springframework.web.bind.annotation.*

// #3267: every simple name a Kotlin file can read unqualified, positional.

// Same-package top-level const, no import.
@RestController
@RequestMapping(SAME_PKG)
class SamePackageController {
    @GetMapping("/a")
    fun a(): String = "ok"
}
