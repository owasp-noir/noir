package com.example.web

import com.example.model.PublicItemRequest
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/items")
class ItemController {
    @PutMapping
    fun replace(@RequestBody request: PublicItemRequest): String = "ok"
}
