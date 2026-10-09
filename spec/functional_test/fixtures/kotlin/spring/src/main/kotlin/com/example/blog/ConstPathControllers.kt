package com.example.blog

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

const val SAME_FILE = "$LOCAL_BASE/same-file"

@RestController
@RequestMapping("/const") // composed from RoutePaths
class ConstPathController(private val repository: ArticleRepository) {
    @GetMapping(RoutePaths.TEMPLATE)
    fun template() = "template"

    @GetMapping(RoutePaths.CONCAT)
    fun concat() = "concat"

    @GetMapping(RoutePaths.BRACED)
    fun braced() = "braced"

    @GetMapping(SAME_FILE)
    fun sameFile() = "same"
}

@RestController
@RequestMapping("/trailing")
class TrailingCommentController(private val repository: ArticleRepository) {
    @GetMapping("/{id}")
    fun show(@PathVariable id: String) = id
}
