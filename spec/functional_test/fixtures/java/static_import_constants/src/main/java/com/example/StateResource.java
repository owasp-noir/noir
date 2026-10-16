package com.example;

import static com.example.Commons.ADMIN_CONTEXT;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

// JAX-RS shares the same constant resolution.
@Path(ADMIN_CONTEXT + "/state")
public class StateResource {
    @GET
    @Path("/liveness")
    public String liveness() {
        return "ok";
    }
}
