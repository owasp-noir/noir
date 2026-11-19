package com.acme

import org.http4k.core.*
import org.http4k.core.Method.*
import org.http4k.routing.*

val userRoutes: RoutingHttpHandler = routes(
    "/" bind GET to { Response(Status.OK) },
    "/{id}" bind GET to { req -> Response(Status.OK).body(req.path("id") ?: "") }
)

fun orderRoutes(): RoutingHttpHandler = routes(
    "/" bind POST to { Response(Status.OK) }
)
