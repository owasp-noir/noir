package org.acme

import io.quarkus.vertx.web.Route
import io.quarkus.vertx.web.RouteBase

// A `/*` inside a Kotlin string template is not a comment opener: reading
// it as one blanked the rest of the file, losing `/k2` and the
// `@RouteBase` prefix of the next class.
@RouteBase(path = "/hk")
class HostileRoutes {
    @Route(path = "/k1") // trailing comment
    fun k1() = ""

    val t = "${"/*"}"

    @Route(path = "/k2")
    fun k2() = ""
}
