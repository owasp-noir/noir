package com.acme.zoo.web.api

import com.acme.zoo.other.Holder.Named.NAMED
import com.acme.zoo.other.Paths.*
import com.acme.zoo.other.TOP_A
import org.springframework.web.bind.annotation.*

// #3267: a top-level const import, a star import and a named companion.
@RestController
@RequestMapping(TOP_A)
class TopImportController {
    @GetMapping("/b")
    fun b(): String = "ok"
}

@RestController
@RequestMapping(BASE)
class StarImportController {
    @GetMapping("/c")
    fun c(): String = "ok"
}

@RestController
@RequestMapping(NAMED)
class NamedCompanionController {
    @GetMapping("/d")
    fun d(): String = "ok"
}
