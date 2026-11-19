package com.acme

import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

object LocalPaths {
    const val ROOT = "/local"
    const val ITEMS = "$ROOT/items"
    const val ITEMS2 = ROOT + "/items2"
}

fun Application.more() {
    routing {
        get(ApiPaths.V1) { call.respondText("x") }
        get(ApiPaths.V1 + "/h-cross-concat") { call.respondText("x") }
        get(LocalPaths.ROOT) { call.respondText("x") }
        get(LocalPaths.ITEMS) { call.respondText("x") }
        get(LocalPaths.ITEMS2) { call.respondText("x") }
    }
}
