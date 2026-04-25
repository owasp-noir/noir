package com.example.api;

import io.dropwizard.jersey.params.IntParam;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.FormParam;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/hello")
@Produces(MediaType.APPLICATION_JSON)
public class HelloResource {

    @GET
    public Response greet(@QueryParam("name") String name) {
        return Response.ok().build();
    }

    @GET
    @Path("/{id}")
    public Response getOne(@PathParam("id") long id,
                           @HeaderParam("X-Trace") String trace) {
        return Response.ok().build();
    }

    @POST
    @Consumes(MediaType.APPLICATION_FORM_URLENCODED)
    public Response submit(@FormParam("subject") String subject,
                           @FormParam("body") String body) {
        return Response.ok().build();
    }

    @PUT
    @Path("/{id}")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response update(@PathParam("id") long id, Greeting payload) {
        return Response.ok().build();
    }

    @DELETE
    @Path("/{id}")
    public Response remove(@PathParam("id") long id) {
        return Response.noContent().build();
    }
}
