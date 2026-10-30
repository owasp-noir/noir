package com.acme.zoo.web.api

import com.acme.zoo.other.*
import com.acme.zoo.other.NestPaths.Admin.ROOT
import org.springframework.web.bind.annotation.*

// #3267: a constant of an `internal object` nested in another object.
@RestController
@RequestMapping(ROOT)
class NestedImportController {
    @GetMapping("/f")
    fun f(): String = "ok"
}

// A package star import, next to a same-package function-local val.
@RestController
@RequestMapping(path = [STAR_API])
class StarPackageController {
    @GetMapping("/g")
    fun g(): String = "ok"
}
