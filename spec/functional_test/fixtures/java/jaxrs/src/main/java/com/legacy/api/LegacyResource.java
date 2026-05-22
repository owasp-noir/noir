package com.legacy.api;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.Response;

@Path("/ping")
public class LegacyResource {
    @GET
    public Response ping() {
        return Response.ok().build();
    }
}
