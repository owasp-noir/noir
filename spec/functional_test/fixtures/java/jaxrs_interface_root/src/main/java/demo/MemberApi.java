package demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.Response;

@Path("/members")
public interface MemberApi {
    @GET
    Response list(@QueryParam("q") String q);

    @GET
    @Path("/{id}")
    Response get(@PathParam("id") long id);
}
