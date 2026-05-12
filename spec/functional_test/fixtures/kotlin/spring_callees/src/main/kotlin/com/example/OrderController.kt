package com.example

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/orders")
class OrderController {

    @GetMapping("/legacy")
    fun legacy(): String {
        AuditLog.write("legacy")
        return getLegacy().toString()
    }

    private fun getLegacy(): String {
        return "legacy"
    }
}
