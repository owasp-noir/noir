package com.example

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
@RestController
annotation class ApiController

@RestController
@RequestMapping("/api/gadgets")
class GadgetController {
    @GetMapping("/list")
    fun list(): String = "[]"
}

@ApiController
@RequestMapping("/api/orders")
class OrderEndpoint {
    @GetMapping("/list")
    fun list(): String = "[]"
}

@RestController
abstract class AbstractResource

// @RestController on the superclass: Spring finds it up the hierarchy.
@RequestMapping("/api/tools")
class ToolResource : AbstractResource() {
    @GetMapping("/list")
    fun list(): String = "[]"
}

// Spring 6 maps only @Controller beans; a type-level @RequestMapping alone
// no longer makes this a handler.
@RequestMapping("/api/widgets")
class WidgetResource {
    @GetMapping("/list")
    fun list(color: String): String = "[]"
}
