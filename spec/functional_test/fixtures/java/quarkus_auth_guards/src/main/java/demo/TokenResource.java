package demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/tokens")
public class TokenResource {
    @GET
    @Path("mine")
    public String mine() { return "secret"; }
}
