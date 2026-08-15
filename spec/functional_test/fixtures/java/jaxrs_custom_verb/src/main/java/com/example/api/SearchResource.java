package com.example.api;

import com.example.annotation.QUERY;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.Response;

@Path("/search")
public class SearchResource {
    @QUERY
    public Response search(FilterDto filters) {
        return Response.ok().build();
    }

    @GET
    @Path("/status")
    public Response status() {
        return Response.ok().build();
    }
}
