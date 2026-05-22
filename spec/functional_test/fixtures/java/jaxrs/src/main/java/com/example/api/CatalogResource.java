package com.example.api;

import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.Response;

@Path("/api")
public class CatalogResource implements CatalogApi {
    public Response showCatalog(String id, String view) {
        return Response.ok().build();
    }

    public Response createCatalog(CatalogBody body) {
        return Response.status(201).build();
    }
}
