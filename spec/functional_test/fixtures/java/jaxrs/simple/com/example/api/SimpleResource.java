package com.simple.api;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/simple")
public class SimpleResource {
    @GET
    public String list() {
        return "simple";
    }
}
