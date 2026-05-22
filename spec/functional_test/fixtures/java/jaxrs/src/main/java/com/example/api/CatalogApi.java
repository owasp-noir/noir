package com.example.api;

import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/catalog")
public interface CatalogApi {
    @GET
    @Path("/{id}")
    Response showCatalog(@PathParam("id") String id,
                         @QueryParam("view") String view);

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    Response createCatalog(CatalogBody body);
}
