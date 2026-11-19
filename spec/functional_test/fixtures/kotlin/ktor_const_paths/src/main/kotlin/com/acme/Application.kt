package com.acme

import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

const val API_PREFIX = "/api/v2"
private const val ADMIN = "$API_PREFIX/admin"

fun Application.module() {
    routing {
        get("$API_PREFIX/a-short") { call.respondText("x") }
        get("${API_PREFIX}/b-braced") { call.respondText("x") }
        get(API_PREFIX + "/c-concat") { call.respondText("x") }
        get("${ApiPaths.V1}/d-object") { call.respondText("x") }
        get(ApiPaths.USERS) { call.respondText("x") }
        get("$ADMIN/e-derived") { call.respondText("x") }
        route("$API_PREFIX/f-route") {
            post("/create") { call.respondText("x") }
        }
        get("/g-real/{id}/$UNKNOWN_SUFFIX") { call.respondText("x") }
    }
}
