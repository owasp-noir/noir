package demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

// A comment that mentions @Authenticated must not itself be a guard.
@Path("/admin")
@Authenticated
public class AdminResource {
    @GET
    public String admin() { return "granted"; }

    @GET
    @Path("off")
    @DenyAll
    public String off() { return "never"; }

    @GET
    @Path("open")
    @PermitAll
    public String open() { return "open"; }

    @GET
    @Path("role")
    @RolesAllowed("user")
    public String role() { return "role"; }
}
