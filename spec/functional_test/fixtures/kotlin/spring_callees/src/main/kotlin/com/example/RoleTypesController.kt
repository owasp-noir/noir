package com.example

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

enum class RoleType {
    ADMIN,
    USER,
}

@RestController
@RequestMapping("/api/roles")
class RoleTypesController {
    @GetMapping("/types")
    fun types(): List<RoleType> {
        val types = RoleType.entries
        return types
    }
}
