package com.example

class LocalRepository(private val auditClient: AuditClient) {
    fun save(value: String): String {
        auditClient.delete(value)
        return value
    }
}

class AuditClient {
    fun delete(value: String): String = value
}
