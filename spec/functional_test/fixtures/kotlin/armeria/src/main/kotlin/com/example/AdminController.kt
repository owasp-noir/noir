package com.example

import com.linecorp.armeria.server.annotation.Get

class AdminController {
    @Get("/stats")
    fun stats(): String = "ok"
}
