package com.example

import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/cities")
class CityController(private val cityService: CityService) {
    @PutMapping("/{id}")
    fun updateCity(@PathVariable id: String): String {
        return cityService.updateCity(id)
    }
}
