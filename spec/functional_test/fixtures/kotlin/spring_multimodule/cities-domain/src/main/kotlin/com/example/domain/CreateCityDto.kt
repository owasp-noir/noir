package com.example.domain

data class CreateCityDto(
    val id: String,
    val name: String,
    val description: String?,
    val location: String
)
