package com.example.api;

import io.dropwizard.auth.Auth;
import jakarta.ws.rs.Path;

// Jersey merges this method's @Auth with the interface method's route.
@Path("/v1/account")
public class AccountResource implements AccountApi {
    public String me(@Auth User user) {
        return "";
    }
}
