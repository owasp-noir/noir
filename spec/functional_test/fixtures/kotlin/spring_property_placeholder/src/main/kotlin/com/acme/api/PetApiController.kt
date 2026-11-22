package com.acme.api

import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*

// Shape emitted by openapi-generator's kotlin-spring templates.
@RestController
@RequestMapping("\${api.base-path:/v2}")
class PetApiController {

    @RequestMapping(
        method = [RequestMethod.GET],
        value = ["/pet/{petId}"],
        produces = ["application/json"]
    )
    fun getPetById(@PathVariable("petId") petId: kotlin.Long): ResponseEntity<String> {
        return ResponseEntity.ok("x")
    }
}

@RestController
@RequestMapping("\${api.prefix}/orders")
class OrderController {
    @GetMapping("/{id}")
    fun get(@PathVariable id: Long) = "x"

    @GetMapping("\${api.missing}/raw")
    fun raw() = "x"
}

@RestController
@RequestMapping(ExternalPaths.BASE)
class ExternalController {
    @GetMapping("/external")
    fun external() = "x"
}

@RestController
@RequestMapping("/published")
class PublishedController {
    @GetMapping(ExternalPaths.LEAF)
    fun unknownLeaf(): String { return "x" }

    @GetMapping(path = ["/$tenant/info", "/public/info"])
    fun info(): String { return "info" }
}
