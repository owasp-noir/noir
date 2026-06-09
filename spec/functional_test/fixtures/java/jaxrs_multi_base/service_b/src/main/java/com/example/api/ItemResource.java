package com.example.api;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/items")
public class ItemResource {
    @GET
    public String list() {
        return "b";
    }
}
