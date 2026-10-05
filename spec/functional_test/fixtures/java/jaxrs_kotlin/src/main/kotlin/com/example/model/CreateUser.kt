package com.example.model

data class CreateUser(
    val name: String,
    val email: String,
    val age: Int = 0,
)
