package com.example.api;

// The single-type import wins over the on-demand one: @Auth here is the app's own.
import com.example.security.Auth;
import io.dropwizard.auth.*;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/v1/custom")
public class CustomAuthResource {
    @GET
    public String custom(@Auth User caller) {
        return "";
    }
}
