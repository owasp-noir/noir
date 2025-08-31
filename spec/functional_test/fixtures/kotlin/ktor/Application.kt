package com.example.ktor

import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.http.*

fun main() {
    embeddedServer(Netty, port = 8080, host = "0.0.0.0") {
        configureRouting()
    }.start(wait = true)
}

fun Application.configureRouting() {
    routing {
        get("/") {
            call.respondText("Hello, World!")
        }
        
        get("/users/{id}") {
            val id = call.parameters["id"]
            call.respondText("User ID: $id")
        }
        
        post("/users") {
            val user = call.receive<User>()
            call.respondText("Created user: ${user.name}")
        }
        
        put("/users/{id}") {
            val id = call.parameters["id"]
            val apiKey = call.request.headers["X-API-Key"]
            call.respondText("Updated user $id with API key $apiKey")
        }
        
        delete("/users/{id}") {
            val id = call.parameters["id"]
            call.respondText("Deleted user $id")
        }
        
        route("/api") {
            get("/status") {
                call.respondText("API is running")
            }
            
            route("/v1") {
                get("/health") {
                    call.respondText("Healthy")
                }
                
                post("/submit") {
                    val data = call.receive<SubmitData>()
                    call.respondText("Submitted: ${data.content}")
                }
                
                get("/items/{itemId}") {
                    val itemId = call.parameters["itemId"]
                    val category = call.parameters["category"]
                    call.respondText("Item $itemId in category $category")
                }
            }
        }
        
        patch("/partial/{resourceId}") {
            val resourceId = call.parameters["resourceId"]
            val authorization = call.request.headers["Authorization"]
            call.respondText("Patched resource $resourceId")
        }
        
        head("/check/{id}") {
            val id = call.parameters["id"]
            call.respond(HttpStatusCode.OK)
        }
        
        options("/settings") {
            call.respond(HttpStatusCode.OK)
        }
    }
}

data class User(val name: String, val email: String)
data class SubmitData(val content: String)