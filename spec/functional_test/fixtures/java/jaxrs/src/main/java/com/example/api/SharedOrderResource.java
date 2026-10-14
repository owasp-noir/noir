package com.example.api;

import com.example.paths.ApiPaths;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

@Path(ApiPaths.SHARED_ORDERS)
public class SharedOrderResource {
    @GET
    @Path("{id}")
    public String get(@PathParam("id") String id) { return ""; }
}
