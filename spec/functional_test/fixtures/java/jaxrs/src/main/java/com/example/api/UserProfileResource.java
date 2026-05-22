package com.example.api;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.Response;

public class UserProfileResource {

    @GET
    public Response getProfile(@QueryParam("include") String include) {
        return Response.ok().build();
    }

    @GET
    @Path("/settings")
    public Response getSettings() {
        return Response.ok().build();
    }
}
