package com.acme

import io.javalin.Javalin
import io.javalin.apibuilder.ApiBuilder.get
import io.javalin.apibuilder.ApiBuilder.path
import io.javalin.http.Handler

object KtUsers {
    val list = Handler { ctx -> ctx.json(listOf<String>()) }
}

fun ktMain() {
    val cache = mutableMapOf<String, String>()
    val app = Javalin.create { config ->
        config.router.apiBuilder {
            path("/kt-api") {
                path("/users") {
                    get(KtUsers.list)
                }
            }
        }
    }
    app.get("/kt-field", KtUsers.list)
    // Map calls with a value expression are not routes.
    cache.put("key", KtUsers.list.toString())
    app.start(7070)
}
