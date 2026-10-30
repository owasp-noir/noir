package com.acme.zoo.web.api

import com.acme.zoo.web.BaseService
import com.acme.zoo.web.BaseService.GROUP_MAPPING
import org.springframework.web.bind.annotation.*

// #3267: Java `static final String` constants read from Kotlin, imported and qualified.
@RestController
@RequestMapping(path = [GROUP_MAPPING])
class GroupController {
    @GetMapping("/{id}/members")
    fun members(): String = "ok"
}

@RestController
@RequestMapping(BaseService.TEAM_MAPPING)
class TeamController {
    @GetMapping("/{id}")
    fun team(): String = "ok"
}
