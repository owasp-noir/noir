package com.example.ktor

import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.http.*

fun Route.extensionRoutes() {
    route("/extension") {
        get {
            call.respondText("Extension route")
        }

        route("/method", HttpMethod.Post) {
            handle {
                call.respondText("Method route")
            }
        }

        route("/query-method") {
            method(HttpMethod.Query) {
                handle {
                    call.respondText("Query method route")
                }
            }
        }
    }
}

// Ktor decorates a placeholder to say how the segment matches: `{name...}`
// is the tailcard, `{name?}` the optional, `{...}` the anonymous tailcard.
// The handler still reads `call.parameters["name"]`, so the decoration is
// not part of the parameter name — and `{...}` names nothing at all.
//
// The tailcard route also names its own placeholder through a variable, so
// the literal opens the brace itself. Wrapping the interpolation in another
// pair produced the URL `/interpolated/{{tail}...}` carrying a path param
// called `{tail`.
fun Route.placeholderShapeRoutes() {
    val tail = "tail"

    get("/listing/{segments...}") {
        call.respondText("Tailcard route")
    }

    get("/optional/{slug?}") {
        call.respondText("Optional route")
    }

    get("/anonymous/{...}") {
        call.respondText("Anonymous tailcard route")
    }

    get("/interpolated/{$tail...}") {
        call.respondText("Interpolated tailcard route")
    }
}
