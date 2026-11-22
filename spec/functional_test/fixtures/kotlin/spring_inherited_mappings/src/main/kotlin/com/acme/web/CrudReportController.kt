package com.acme.web

import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/crud")
class CrudReportController : AbstractCrudController() {
    override fun remove(id: String) {}
    fun remove(id: Long) {}

    @PostMapping
    fun create(): String = "created"
}
