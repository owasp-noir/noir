package demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.Response;

// The class's own @Path wins and the interface's is joined below it, as before.
@Path("/v2")
public class TeamResource implements TeamApi {
    @Override
    public Response team(String name) { return Response.ok().build(); }
}

@Path("/teams")
interface TeamApi {
    @GET
    @Path("/{name}")
    Response team(@PathParam("name") String name);
}

// Implements an interface that carries no @Path: not a resource.
class AuditLog implements Runnable {
    @GET
    @Path("/audit")
    public Response dump() { return Response.ok().build(); }

    @Override
    public void run() {}
}
