package com.example

import org.http4k.core.Method.GET
import org.http4k.core.Response
import org.http4k.core.Status
import org.http4k.routing.bind
import org.http4k.routing.routes

val app = routes(
    com.example.Routes.ITEM bind GET to { Response(Status.OK) }
)
