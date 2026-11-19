package com.acme

import jakarta.servlet.http.HttpServletRequest
import org.springframework.data.domain.Pageable
import org.springframework.http.HttpHeaders
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/kt/reports")
class ReportController {
    @GetMapping
    fun list(pageable: Pageable) = "x"

    @GetMapping("/raw")
    fun raw(request: HttpServletRequest): String {
        val from = request.getParameter("from")
        val tenant = request.getHeader("X-Tenant")
        return "x"
    }

    @GetMapping("/headers")
    fun headers(@RequestHeader headers: HttpHeaders): String? = headers.getFirst("X-Trace-Id")

    @GetMapping("/map")
    fun map(@RequestParam params: Map<String, String>): String? = params["cursor"] + params.get("limit")
}

@RestController
@RequestMapping("/kt/search")
class SearchController {
    // A Pageable after an annotated argument is still paging input.
    @GetMapping
    fun search(@RequestParam q: String, pageable: Pageable) = "x"

    @PostMapping("/form")
    fun form(request: HttpServletRequest): String = request.getParameter("token") ?: "x"
}
