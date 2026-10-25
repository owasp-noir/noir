package com.example.api;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

public interface AccountApi {
    @GET
    @Path("/me")
    String me(User user);
}
