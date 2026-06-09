package com.example.web

import com.example.domain.CreateCityDto
import com.example.domain.UpdateCityDto
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/cities")
class CityController {
    @PostMapping
    fun create(@RequestBody city: CreateCityDto): String = city.name

    @PutMapping("/{id}")
    fun update(@PathVariable id: String, @RequestBody city: UpdateCityDto): String = id
}
