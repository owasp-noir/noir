package org.acme;

import io.quarkus.runtime.annotations.RegisterForReflection;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.Response;

@Path("/configured")
@RegisterForReflection
public class ConfiguredResource {
    @GET
    public Response get() {
        return Response.ok().build();
    }
}
