package demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("")
public class RootResource {
    @GET
    @Path("/")
    public String root() { return ""; }
}
