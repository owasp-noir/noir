package com.acme.build

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

// A source package that happens to be named `build`: not build output.
@RestController
@RequestMapping("/build")
class BuildController {
    @GetMapping("/list")
    fun list(): String = "ok"
}
