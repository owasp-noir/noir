package com.acme.web

import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/crud")
class CrudReportController : AbstractCrudController() {
    @PostMapping
    fun create(): String = "created"
}
