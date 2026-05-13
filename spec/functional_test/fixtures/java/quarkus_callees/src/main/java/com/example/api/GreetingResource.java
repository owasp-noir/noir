package com.example.api;

import io.quarkus.runtime.annotations.RegisterForReflection;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.Response;
import org.jboss.resteasy.reactive.RestPath;
import org.jboss.resteasy.reactive.RestQuery;

@Path("/greetings")
@RegisterForReflection
public class GreetingResource {
    private final GreetingService service = new GreetingService();

    @POST
    @Path("/{id}")
    public Response create(@RestPath long id,
                           @RestQuery("dry_run") boolean dryRun) {
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

class GreetingService {
    void save(long id, boolean dryRun) {}
}

class AuditLog {
    static void write(String event) {}
}
