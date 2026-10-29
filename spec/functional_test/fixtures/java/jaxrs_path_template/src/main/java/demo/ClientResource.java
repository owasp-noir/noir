package demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

@Path("/clients")
public class ClientResource {
    @GET
    @Path("{client-uuid}/roles/{role.name}")
    public String role(@PathParam("client-uuid") String id, @PathParam("role.name") String role) { return ""; }

    @GET
    @Path("{clientId}/scopes")
    public String scopes(@PathParam("clientId") String id) { return ""; }
}
