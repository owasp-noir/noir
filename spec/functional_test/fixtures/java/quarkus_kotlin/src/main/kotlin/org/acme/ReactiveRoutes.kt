package org.acme

import io.quarkus.vertx.web.Body
import io.quarkus.vertx.web.Param
import io.quarkus.vertx.web.Route
import io.vertx.ext.web.RoutingContext
import jakarta.enterprise.context.ApplicationScoped

@ApplicationScoped
class ReactiveRoutes(private val audit: AuditLog) {
    @Route(path = "/ping", methods = [Route.HttpMethod.GET])
    fun ping(@Param("name") name: String?): String = "pong $name"

    @Route(methods = [Route.HttpMethod.POST])
    fun createItem(@Body item: Item, rc: RoutingContext) {
        audit.record(item)
    }
}

data class Item(val sku: String)
