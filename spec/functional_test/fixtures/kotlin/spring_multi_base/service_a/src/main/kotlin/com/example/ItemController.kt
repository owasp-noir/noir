package com.example

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RestController

@RestController
class ItemController {
    @GetMapping(com.example.Routes.ITEM)
    fun list(): String = "a"
}
