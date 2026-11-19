package com.acme

import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.server.util.*

fun Application.module() {
    routing {
        // `getOrFail` / `getAll` on a `receiveParameters()` value.
        post("/a-form-getorfail") {
            val formParameters = call.receiveParameters()
            val title = formParameters.getOrFail("title")
            val body = formParameters["body"]
            val tags = formParameters.getAll("tags")
            call.respondText(title)
        }
        get("/b-path-getorfail/{id}") {
            val id = call.parameters.getOrFail<Int>("id").toInt()
            val page = call.parameters.getOrFail("page")
            call.respondText("$id")
        }
        get("/c-query-variants") {
            val a = call.request.queryParameters["plain"]
            val b = call.request.queryParameters.getOrFail("orfail")
            val c = call.request.queryParameters.getAll("all")
            val d = call.queryParameters["ktor3"]
            val e = call.request.queryParameters.get("getcall")
            call.respondText("x")
        }
        get("/d-cookie-header") {
            val sid = call.request.cookies["sid"]
            val ua = call.request.headers["User-Agent"]
            val auth = call.request.header("Authorization")
            val all = call.request.headers.getAll("X-Multi")
            call.respondText("x")
        }
        get("/e-local-alias") {
            val params = call.request.queryParameters
            val q = params["aliased"]
            val h = call.request.headers
            val t = h["X-Aliased"]
            call.respondText("x")
        }
        post("/f-inline-form") {
            val user = call.receiveParameters()["user"]
            call.respondText("x")
        }
    }
}
