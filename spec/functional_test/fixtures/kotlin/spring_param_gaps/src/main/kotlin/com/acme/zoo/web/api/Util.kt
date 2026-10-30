package com.acme.zoo.web.api

// A function-local val is not a package member: it must not shadow the
// star-imported `STAR_API`.
fun helper(): String {
    val STAR_API = "/zoo-local-junk"
    return STAR_API
}
