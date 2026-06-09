package com.example.api

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping

@RequestMapping("/api/users")
interface UserApi {
    @GetMapping("/{id}")
    fun show(@PathVariable id: String): String

    @PostMapping
    fun create(@RequestBody user: UserCreate): String
}

data class UserCreate(val name: String, val email: String)
