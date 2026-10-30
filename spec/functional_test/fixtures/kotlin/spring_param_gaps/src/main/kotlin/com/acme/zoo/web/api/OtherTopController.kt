package com.acme.zoo.web.api

import com.acme.zoo.web.TOP_A
import org.springframework.web.bind.annotation.*

// #3267: the keyword form binds the imported top-level const, not the
// first-declared `TOP_A`.
@RestController
@RequestMapping(path = [TOP_A])
class OtherTopController {
    @GetMapping("/e")
    fun e(): String = "ok"
}
