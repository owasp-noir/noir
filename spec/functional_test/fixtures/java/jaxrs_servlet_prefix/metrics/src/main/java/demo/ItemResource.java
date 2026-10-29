package demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

@Path("/items")
public class ItemResource {
    @GET
    @Path("/{id}")
    public String get(@PathParam("id") String id) { return id; }
}
