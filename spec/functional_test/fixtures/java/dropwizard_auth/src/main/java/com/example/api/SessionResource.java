package com.example.api;

import com.example.entities.CreateSession;
import com.example.entities.Node;
import com.example.entities.Profile;
import com.example.other.Address;
import io.dropwizard.auth.Auth;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.HttpHeaders;
import java.util.Optional;

@Path("/v1/session")
public class SessionResource {

    // Required principal: AuthDynamicFeature answers 401 without credentials.
    @GET
    @Path("/{id}")
    public String show(@Auth User user, @PathParam("id") String id,
                       @HeaderParam(HttpHeaders.USER_AGENT) String userAgent) {
        return id;
    }

    // Optional principal: anonymous callers get through.
    @POST
    public String create(@Auth Optional<User> maybeUser, CreateSession request,
                         @Context ContainerRequestContext context) {
        return "";
    }

    // No principal at all. Profile's `home` unwraps com.example.entities.Address
    // (resolved from Profile's own package), not the Address imported here.
    @PUT
    @Path("/profile")
    public String profile(Profile profile) {
        return "";
    }

    @PUT
    @Path("/planet")
    public String planet(Address address) {
        return "";
    }

    @POST
    @Path("/node")
    public String node(Node node) {
        return "";
    }
}
