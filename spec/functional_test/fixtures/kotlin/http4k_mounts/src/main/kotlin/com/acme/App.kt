package com.acme

import org.http4k.core.*
import org.http4k.core.Method.*
import org.http4k.routing.*

val health = routes("/ping" bind GET to { Response(Status.OK) })

// Sub-apps bound under a prefix by name, by call and inline.
val app: HttpHandler = routes(
    "/users" bind userRoutes,
    "/orders" bind orderRoutes(),
    "/internal" bind health,
    "/inline" bind routes("/x" bind GET to { Response(Status.OK) })
)
