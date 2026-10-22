package org.acme

import jakarta.enterprise.context.ApplicationScoped
import jakarta.ws.rs.GET
import jakarta.ws.rs.POST
import jakarta.ws.rs.Path
import jakarta.ws.rs.Produces
import jakarta.ws.rs.core.MediaType
import org.jboss.resteasy.reactive.RestHeader
import org.jboss.resteasy.reactive.RestPath
import org.jboss.resteasy.reactive.RestQuery

@ApplicationScoped
@Path("/hello")
@Produces(MediaType.APPLICATION_JSON)
class GreetingResource(private val service: GreetingService) {
    @GET
    fun hello(@RestQuery name: String?, @RestHeader("X-Lang") lang: String?): String = service.greet(name, lang)

    @GET
    @Path("/{id}")
    fun byId(@RestPath id: Long) = service.find(id)

    @POST
    fun create(greeting: Greeting) = service.save(greeting)
}

data class Greeting(val message: String, val lang: String = "en")
