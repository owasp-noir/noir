package com.example

import io.javalin.Javalin

// Exactly `Tests.kt`: a class named like the suffix, not a test class.
class Tests {
    fun app(): Javalin {
        val app = Javalin.create()
        app.get("/tests-kt/real") { ctx -> ctx.result("ok") }
        return app
    }
}
