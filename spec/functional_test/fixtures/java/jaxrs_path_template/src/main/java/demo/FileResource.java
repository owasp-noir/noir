package demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

@Path("/files")
public class FileResource {
    @GET
    @Path("{path: .+}")
    public String read(@PathParam("path") String path) { return ""; }

    @GET
    @Path("by-id/{id: [0-9]+}")
    public String byId(@PathParam("id") String id) { return ""; }
}
