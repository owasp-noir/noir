package demo.api;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/a")
public class AResource {
    @GET
    public String get() { return "a"; }
}
