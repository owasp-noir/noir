package com.acme.zoo.web.api

import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping(ITEM_BASE_PATH)
class ItemController {
    @GetMapping("/list")
    fun list(): String = "ok"

    companion object {
        const val ITEM_BASE_PATH: String = "/admin/items"
    }
}
