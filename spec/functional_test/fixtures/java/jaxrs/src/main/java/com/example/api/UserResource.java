package com.example.api;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.PATCH;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.CookieParam;
import jakarta.ws.rs.FormParam;
import jakarta.ws.rs.BeanParam;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/users")
@Produces(MediaType.APPLICATION_JSON)
public class UserResource {
    private static final String SIZE_PARAM = "size";
    private static final String TRACE_HEADER = "X-Trace";

    @GET
    public Response listUsers(@QueryParam("page") @DefaultValue("0") int page,
                              @QueryParam(SIZE_PARAM) int size) {
        return Response.ok().build();
    }

    @GET
    @Path("/{id}")
    public Response getUser(@PathParam("id") long id,
                            @HeaderParam(TRACE_HEADER) String trace) {
        return Response.ok().build();
    }

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    public Response createUser(User body) {
        return Response.status(201).build();
    }

    @POST
    @Path("/login")
    @Consumes(MediaType.APPLICATION_FORM_URLENCODED)
    public Response login(@FormParam("username") String username,
                          @FormParam("password") String password) {
        return Response.ok().build();
    }

    @PUT
    @Path("/{id}")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response updateUser(@PathParam("id") long id, User body) {
        return Response.ok().build();
    }

    @DELETE
    @Path("/{id}")
    public Response deleteUser(@PathParam("id") long id,
                               @CookieParam("session") String session) {
        return Response.noContent().build();
    }

    @PATCH
    @Path("/{id}")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response patchUser(@PathParam("id") long id,
                              @BeanParam UserFilter filter) {
        return Response.ok().build();
    }

    @Path("/{id}/profile")
    public UserProfileResource profile(@PathParam("id") long id) {
        return new UserProfileResource();
    }
}
