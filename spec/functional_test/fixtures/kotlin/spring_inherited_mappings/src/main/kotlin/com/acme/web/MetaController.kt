package com.acme.web

import org.springframework.web.bind.annotation.*

@ApiController
class MetaController {
    @GetMapping("/plain")
    fun plain() = "x"

    @AuditGet
    fun audit() = "x"
}
