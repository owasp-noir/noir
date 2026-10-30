package com.acme.zoo.web.api

import com.acme.zoo.web.api.ItemController.Companion.ITEM_BASE_PATH
import org.springframework.web.bind.annotation.*

// #3267: positional bare constant declared in another file.
@RestController
@RequestMapping(ITEM_BASE_PATH)
class ItemAdminController {
    @PostMapping("{id}/notice")
    fun notice(): String = "ok"
}
