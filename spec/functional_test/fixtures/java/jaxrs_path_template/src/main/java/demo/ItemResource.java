package demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;

@Path("/items")
public class ItemResource {
    @GET
    @Path("/")
    public String list() { return ""; }

    @POST
    public String create() { return ""; }

    @GET
    @Path("archived/")
    public String archived() { return ""; }
}
