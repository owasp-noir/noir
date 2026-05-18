// Regression guard: Gradle parks JVM test sources under
// `src/test/kotlin/...`. Routes registered there exercise the
// framework's routing DSL but never serve real traffic. None of the
// URLs below should appear in the fixture's expected-endpoints list.
package com.example

import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.response.*
import org.junit.jupiter.api.Test

class ApplicationTest {
    @Test
    fun testRoutes() {
        // Inline test app that registers routes; the analyzer should
        // skip this file entirely because of its `/src/test/` path.
        val module: Application.() -> Unit = {
            routing {
                get("/should-not-appear-test-get") { call.respondText("") }
                post("/should-not-appear-test-post") { call.respondText("") }
            }
        }
    }
}
