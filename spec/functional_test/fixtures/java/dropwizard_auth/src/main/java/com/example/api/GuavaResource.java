package com.example.api;

import com.google.common.base.Optional;
import com.google.common.net.HttpHeaders;
import io.dropwizard.auth.Auth;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.Path;

@Path("/v1/guava")
public class GuavaResource {
    // Guava's Optional is not java.util.Optional: the authenticator filter applies.
    @GET
    @Path("/required")
    public String required(@Auth Optional<User> user, @HeaderParam(HttpHeaders.CONTENT_MD5) String md5) {
        return "";
    }

    @GET
    @Path("/optional")
    public String optional(@Auth java.util.Optional<User> user) {
        return "";
    }
}
