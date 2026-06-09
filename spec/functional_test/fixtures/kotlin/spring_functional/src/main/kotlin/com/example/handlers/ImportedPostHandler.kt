package com.example.handlers

import org.springframework.stereotype.Component
import org.springframework.web.reactive.function.server.ServerRequest
import org.springframework.web.reactive.function.server.ServerResponse
import org.springframework.web.reactive.function.server.bodyValueAndAwait
import org.springframework.web.reactive.function.server.ServerResponse.ok
import kotlin.random.Random

@Component
class ImportedPostHandler(private val importedPosts: ImportedPostRepository) {
    private val log = org.slf4j.LoggerFactory.getLogger(ImportedPostHandler::class.java)

    suspend fun show(req: ServerRequest): ServerResponse {
        log.info("show imported post")
        java.util.UUID.fromString("00000000-0000-0000-0000-000000000000").toString()
        Thread.sleep(1)
        Random.nextLong()
        return ok().bodyValueAndAwait(importedPosts.load(req.queryParam("id")).let { it })
    }
}

class ImportedPostRepository {
    fun load(id: java.util.Optional<String>): String = id.orElse("missing")
}
