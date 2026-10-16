package com.example

import io.javalin.Javalin

// A test-kit controller published from src/main/kotlin: not served by the app.
class FormBindingTest {
    fun app(): Javalin {
        val app = Javalin.create()
        app.get("/form-binding-kt/test-kit") { ctx -> ctx.result("ok") }
        return app
    }
}
