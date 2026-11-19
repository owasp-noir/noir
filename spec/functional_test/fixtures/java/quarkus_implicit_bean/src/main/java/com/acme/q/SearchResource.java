package com.acme.q;

import jakarta.ws.rs.*;

@Path("/search")
public class SearchResource {
    @GET
    @Path("/implicit")
    public String implicit(Params params) { return "x"; }

    @GET
    @Path("/explicit")
    public String explicit(@BeanParam Params params) { return "x"; }

    @POST
    @Path("/items")
    @Consumes("application/json")
    public String create(Item item) { return "x"; }
}
