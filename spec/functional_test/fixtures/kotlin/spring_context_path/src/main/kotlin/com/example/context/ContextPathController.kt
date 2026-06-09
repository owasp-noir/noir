package com.example.context

import org.springframework.graphql.data.method.annotation.Argument
import org.springframework.graphql.data.method.annotation.QueryMapping
import org.springframework.stereotype.Controller
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/users")
class ContextPathController(private val profileService: ProfileService) {
    @GetMapping("/{id}")
    fun user(@PathVariable id: String): Profile {
        return profileService.find(id)
    }
}

@Controller
class ContextPathGraphqlController(private val profileService: ProfileService) {
    @QueryMapping
    fun profile(@Argument id: String): Profile {
        return profileService.find(id)
    }
}

class ProfileService {
    fun find(id: String): Profile = Profile(id)
}

data class Profile(val id: String)
