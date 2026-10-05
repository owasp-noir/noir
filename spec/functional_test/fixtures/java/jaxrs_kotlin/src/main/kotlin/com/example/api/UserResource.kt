package com.example.api

import com.example.model.CreateUser
import jakarta.inject.Singleton
import jakarta.ws.rs.Consumes
import jakarta.ws.rs.CookieParam
import jakarta.ws.rs.DELETE
import jakarta.ws.rs.DefaultValue
import jakarta.ws.rs.FormParam
import jakarta.ws.rs.GET
import jakarta.ws.rs.HeaderParam
import jakarta.ws.rs.POST
import jakarta.ws.rs.PUT
import jakarta.ws.rs.Path
import jakarta.ws.rs.PathParam
import jakarta.ws.rs.Produces
import jakarta.ws.rs.QueryParam
import jakarta.ws.rs.core.Context
import jakarta.ws.rs.core.MediaType
import jakarta.ws.rs.core.Response
import jakarta.ws.rs.core.UriInfo

const val USERS_PATH = "/users"

@Singleton
@Path(USERS_PATH)
@Produces(MediaType.APPLICATION_JSON)
class UserResource(private val service: UserService) {
    @GET
    fun list(
        @QueryParam("page") @DefaultValue("1") page: Int,
        @HeaderParam("X-Tenant") tenant: String?,
    ): List<User> = service.list(page, tenant)

    @GET
    @Path("/{id}")
    fun get(@PathParam("id") id: Long, @CookieParam("session") session: String?): User = service.find(id)

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    fun create(user: CreateUser, @Context uriInfo: UriInfo): Response {
        service.save(user)
        return Response.created(uriInfo.requestUri).build()
    }

    @PUT
    @Path("/{id}/avatar")
    @Consumes(MediaType.APPLICATION_FORM_URLENCODED)
    fun avatar(@PathParam("id") id: Long, @FormParam("url") url: String): Response = service.avatar(id, url)

    @DELETE
    @Path("/{id}")
    fun delete(@PathParam("id") id: Long) = service.delete(id)

    @Path("/{id}/orders")
    fun orders(@PathParam("id") id: Long): OrderResource = OrderResource(id)
}

class OrderResource(private val userId: Long) {
    @GET
    fun list(@QueryParam("status") status: String?) = OrderService.list(userId, status)
}
