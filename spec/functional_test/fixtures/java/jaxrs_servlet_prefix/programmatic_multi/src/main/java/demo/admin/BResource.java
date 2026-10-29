package demo.admin;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/b")
public class BResource {
    @GET
    public String get() { return "b"; }
}
