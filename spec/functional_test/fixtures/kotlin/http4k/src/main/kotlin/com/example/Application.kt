package com.example

import org.http4k.core.Method.DELETE
import org.http4k.core.Method.GET
import org.http4k.core.Method.PATCH
import org.http4k.core.Method.POST
import org.http4k.core.Method.PUT
import org.http4k.core.Request
import org.http4k.core.Response
import org.http4k.core.Status.Companion.OK
import org.http4k.routing.bind
import org.http4k.routing.routes

val app = routes(
    "/hello" bind GET to { req: Request ->
        val name = req.query("name")
        Response(OK).body("hello $name")
    },

    "/users" bind POST to { req: Request ->
        val body = req.bodyString()
        Response(OK).body(body)
    },

    "/users/{id}" bind PUT to { req: Request ->
        val token = req.header("X-API-Key")
        val body = req.bodyString()
        Response(OK)
    },

    "/api" bind routes(
        "/status" bind GET to { _: Request -> Response(OK) },
        "/v1" bind routes(
            "/health" bind GET to { _: Request -> Response(OK) },
            "/submit" bind POST to { req: Request ->
                val body = req.bodyString()
                val token = req.header("X-Token")
                Response(OK)
            },
            "/items/{itemId}" bind GET to { req: Request ->
                val category = req.query("category")
                Response(OK)
            }
        )
    ),

    "/sessions/{id}" bind DELETE to { req: Request ->
        Response(OK)
    },

    "/profile" bind PATCH to { req: Request ->
        val email = req.form("email")
        val phone = req.form("phone")
        Response(OK)
    }
)
