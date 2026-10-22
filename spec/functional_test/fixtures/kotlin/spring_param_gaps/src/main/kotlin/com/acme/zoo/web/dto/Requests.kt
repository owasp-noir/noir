package com.acme.zoo.web.dto

data class FeedRequest(val animalName: String, val grams: Int? = null)

data class CleanRequest(val cage: String)
