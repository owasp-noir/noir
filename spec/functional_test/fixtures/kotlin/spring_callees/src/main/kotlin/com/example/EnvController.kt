package com.example

import org.springframework.beans.factory.annotation.Value
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/env")
class EnvController {
    @Value("\${PASS:#{null}}")
    lateinit var password: String

    @GetMapping("/password")
    fun password(): String = password
}
