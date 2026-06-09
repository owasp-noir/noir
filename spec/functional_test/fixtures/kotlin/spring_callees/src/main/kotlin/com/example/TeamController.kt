package com.example

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/teams")
class TeamController(private val searchEngine: SearchEngine) {
    @GetMapping("/{nation}")
    fun teams(@PathVariable nation: String): String {
        return searchEngine.getFilteredNames(nation)
    }
}
