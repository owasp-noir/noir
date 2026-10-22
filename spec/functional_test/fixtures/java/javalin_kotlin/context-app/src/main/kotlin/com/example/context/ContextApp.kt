package com.example.context

import io.javalin.Javalin

fun main() {
    Javalin.create { config ->
        config.router.contextPath = "/ctx" // mounted behind the gateway
    }.get("/status") { ctx -> ctx.result("ok") }
        .post("/reload") { ctx -> ctx.result("reloaded") }
        .start(7071)
}
