package com.example

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

// No routes on purpose: every endpoint this fixture produces comes from
// `spring.web.resources.static-locations` in application.properties, which
// is what the static-resource walk is asserted on.
@SpringBootApplication
class StaticApp

fun main(args: Array<String>) {
    runApplication<StaticApp>(*args)
}
