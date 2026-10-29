package com.example.api;

import com.example.dto.ItemSearch;
import com.example.dto.CreateItemRequest;
import jakarta.ws.rs.*;

public class ItemResource {
    @GET
    public String list(@PathParam("userId") String userId, @BeanParam ItemSearch search) { return ""; }

    @POST
    @Consumes("application/json")
    public String create(@PathParam("userId") String userId, CreateItemRequest body) { return ""; }
}
