package com.example.api;

import io.dropwizard.core.Application;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.Response;

@Path("/hello")
public class HelloResource {
    private final HelloService service = new HelloService();

    @POST
    @Path("/{id}")
    public Response create(@PathParam("id") long id,
                           @QueryParam("dry_run") boolean dryRun) {
        validate(id);
        service.save(id, dryRun);
        AuditLog.write("create");
        return Response.ok().build();
    }

    @GET
    @Path("/profile")
    public Response profile() {
        String profile = this.buildProfile();
        AuditLog.write(profile);
        return Response.ok(profile).build();
    }

    private void validate(long id) {}

    private String buildProfile() {
        return "profile";
    }
}

class HelloService {
    void save(long id, boolean dryRun) {}
}

class AuditLog {
    static void write(String event) {}
}
