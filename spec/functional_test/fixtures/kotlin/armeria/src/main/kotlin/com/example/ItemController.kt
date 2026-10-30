package com.example

import com.linecorp.armeria.server.annotation.Get
import com.linecorp.armeria.server.annotation.Param
import com.linecorp.armeria.server.annotation.Post

class ItemController {
    @Get("/{id}")
    fun get(@Param("id") id: String): String = id

    @Post("/search")
    fun search(@Param("q") q: String): String = q
}
