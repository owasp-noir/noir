package com.acme.web

import org.springframework.web.bind.annotation.*

abstract class AbstractCrudController {
    @GetMapping("/list")
    fun list(@RequestParam(defaultValue = "0") page: Int): String = "list"

    @GetMapping("/{id}")
    fun get(@PathVariable id: String): String = id

    @DeleteMapping("/{id}")
    open fun remove(@PathVariable id: String) {}
}
