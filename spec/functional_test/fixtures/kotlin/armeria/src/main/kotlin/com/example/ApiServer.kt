package com.example

import com.linecorp.armeria.common.HttpResponse
import com.linecorp.armeria.server.Server

fun main() {
    val server = Server.builder()
        .http(8080)
        .annotatedService("/api/items", ItemController())
        .annotatedService(UserController::class.java.getDeclaredConstructor().newInstance())
        .service("/health") { _, _ -> HttpResponse.of("ok") }
        .annotatedService()
        .pathPrefix("/admin")
        .build(AdminController())
        .build()
    server.start().join()
}
