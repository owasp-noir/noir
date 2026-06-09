package com.example

import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/scoped")
class ScopedController(private val localRepository: LocalRepository) {
    @PostMapping
    fun create(): String {
        return localRepository.save("ok")
    }
}

class LocalRepository(private val databaseClient: DatabaseClient) {
    fun save(value: String): String {
        databaseClient.insert(value)
        return value
    }
}

class DatabaseClient {
    fun insert(value: String): String = value
}
