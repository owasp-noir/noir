package com.example

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/webclient")
class WebClientController(private val client: DownstreamClient) {

    @GetMapping("/{id}")
    fun details(@PathVariable id: String): String = withDetails(id)

    private fun withDetails(id: String): String {
        return client.get("/items/$id")
    }
}
