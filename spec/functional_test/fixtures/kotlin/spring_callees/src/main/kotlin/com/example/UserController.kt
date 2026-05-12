package com.example

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/users")
class UserController(private val service: UserService) {

    @PostMapping("/")
    fun createUser(): String {
        val saved = service.save("hahwul")
        AuditLog.write(saved)
        return saved
    }

    @GetMapping("/profile")
    fun profile(): String {
        val built = this.buildProfile()
        AuditLog.write(built)
        return built
    }

    private fun buildProfile(): String {
        return "profile"
    }
}
