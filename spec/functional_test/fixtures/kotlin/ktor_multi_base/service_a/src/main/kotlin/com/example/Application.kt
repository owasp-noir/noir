package com.example

import io.ktor.server.routing.get
import io.ktor.server.routing.routing

fun configureRouting() {
    routing {
        get(com.example.Routes.ITEM) {
        }
    }
}
