package com.example

// Not com.linecorp.armeria.server.annotation.Get: an HTTP client's own
// annotation, so nothing here is an Armeria route.
import com.example.client.Get

interface LegacyClient {
    @Get("/legacy/items")
    fun items(): String
}
