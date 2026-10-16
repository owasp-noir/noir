package com.example;

import static com.example.Commons.*;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

// No BASE of its own: the wildcard import supplies it.
@Path(BASE + "/imp")
public class ImportedResource {
    @GET
    @Path("/x")
    public String x() {
        return "ok";
    }
}
