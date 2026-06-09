package com.example

class AuditGateway {
    fun record(value: String) {
    }

    fun find(value: String): java.util.Optional<String> {
        return java.util.Optional.of(value)
    }
}
