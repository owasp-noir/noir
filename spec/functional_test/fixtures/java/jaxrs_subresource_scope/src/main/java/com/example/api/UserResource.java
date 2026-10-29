package com.example.api;

import jakarta.ws.rs.Path;

@Path("/users/{userId}")
public class UserResource {
    @Path("items")
    public Class<ItemResource> items() { return ItemResource.class; }
}
