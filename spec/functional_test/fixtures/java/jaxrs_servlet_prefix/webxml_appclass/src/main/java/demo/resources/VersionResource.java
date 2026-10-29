package demo.resources;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/v3/version")
public class VersionResource {
    @GET
    public String get() { return "3"; }
}
