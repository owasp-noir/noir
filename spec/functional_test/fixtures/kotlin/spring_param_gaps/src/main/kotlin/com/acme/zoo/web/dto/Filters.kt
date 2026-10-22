package com.acme.zoo.web.dto

data class SearchFilter(val id: Long? = null, val species: String? = null)

data class SprocketBatch(val items: List<String>, val note: String)

data class PingReq(val who: String) {
    val derivedKey: String by lazy { "k-" + who }
}
