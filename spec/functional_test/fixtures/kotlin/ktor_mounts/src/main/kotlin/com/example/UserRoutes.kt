package com.example

import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Route.userRoutes() {
    get("sign") {
        call.respondText("signed")
    }
    route("vote") {
        get {
            call.respondText("votes")
        }
    }
}

fun Route.adminRoutes() {
    get("admin") {
        call.respondText("admin")
    }
}

fun Route.publicRoutes() {
    get("public") {
        call.respondText("public")
    }
}

fun Route.optionalRoutes() {
    get("maybe") {
        call.respondText("maybe")
    }
}

fun Route.sharedRoutes() {
    get("/shared") {
        call.respondText("shared")
    }
}

fun Route.unplacedRoutes() {
    get("/free") {
        call.respondText("free")
    }
}

fun Route.neverMountedRoutes() {
    get("/orphan") {
        call.respondText("orphan")
    }
}
