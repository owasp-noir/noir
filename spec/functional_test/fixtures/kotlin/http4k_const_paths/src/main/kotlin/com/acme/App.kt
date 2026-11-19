package com.acme

import org.http4k.core.*
import org.http4k.core.Method.*
import org.http4k.routing.*

const val PREFIX = "/v1"

val app: HttpHandler = routes(
    "$PREFIX/a-short" bind GET to { Response(Status.OK) },
    PREFIX + "/b-concat" bind GET to { Response(Status.OK) },
    Paths.API bind GET to { Response(Status.OK) },
    "${Paths.API}/c-object" bind PATCH to { Response(Status.OK) }
)
