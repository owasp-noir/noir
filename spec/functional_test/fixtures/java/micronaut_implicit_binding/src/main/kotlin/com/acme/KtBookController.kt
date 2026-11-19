package com.acme

import io.micronaut.http.annotation.*

@Controller("/kt-books")
class KtBookController {
    @Get("/search")
    fun search(title: String, author: String?, max: Int?): String = "x"

    @Get("/search-explicit")
    fun searchExplicit(@QueryValue title: String, @QueryValue author: String?): String = "x"

    @Post("/login")
    fun login(username: String, password: String): String = "x"
}
