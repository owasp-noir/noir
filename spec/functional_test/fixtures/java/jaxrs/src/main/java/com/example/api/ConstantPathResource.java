package com.example.api;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.Response;

@Path(ConstantPathResource.API_PREFIX + "/constant")
public class ConstantPathResource {

    public static final String API_PREFIX = "/api";
    private static final String SEARCH = "/search";

    @GET
    @Path(SEARCH)
    public Response search(@QueryParam("q") String query) {
        return Response.ok().build();
    }
}
