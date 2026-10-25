package com.example.audit;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

// Unlike @io.dropwizard.auth.Auth, this package's own @Auth only logs the caller.
@Path("/v1/audit")
public class AuditResource {
    @GET
    public String audit(@Auth String caller) {
        return "";
    }
}
