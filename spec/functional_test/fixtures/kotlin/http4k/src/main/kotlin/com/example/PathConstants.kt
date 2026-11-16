package com.example

import org.http4k.core.Method.GET
import org.http4k.core.Request
import org.http4k.core.Response
import org.http4k.core.Status.Companion.OK
import org.http4k.routing.bind
import org.http4k.routing.routes

object PublicPaths {
    const val EXAMPLE = "}"
    const val HEALTH = "/constant-health"
}

val constantRoutes = routes(
    PublicPaths.HEALTH bind GET to { _: Request -> Response(OK) }
)
