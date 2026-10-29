package demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/public")
public class PublicResource {
    @GET
    @Path("page")
    public String page() { return "page"; }

    // @Authenticated
    @GET
    @Path("note")
    public String note() { return "note"; }
}
