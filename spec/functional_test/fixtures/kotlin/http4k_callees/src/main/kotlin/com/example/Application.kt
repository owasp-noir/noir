package com.example

import org.http4k.core.Method.GET
import org.http4k.core.Method.POST
import org.http4k.core.Request
import org.http4k.core.Response
import org.http4k.core.Status.Companion.OK
import org.http4k.routing.bind
import org.http4k.routing.routes

val app = routes(
    "/users" bind POST to { req: Request ->
        val name = req.query("name")
        val saved = UserService.save(name)
        AuditLog.write(saved)
        Response(OK)
    },

    "/profile" bind GET to { _: Request ->
        val built = buildProfile()
        AuditLog.write(built)
        Response(OK)
    },

    "/legacy" bind GET to { _: Request ->
        AuditLog.write("legacy")
        val out = getLegacy().toString()
        Response(OK)
    }
)

fun buildProfile(): String = "profile"
fun getLegacy(): String = "legacy"
