package demo;

import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.Response;

public class MemberResource implements MemberApi {
    @Override
    public Response list(String q) { return Response.ok().build(); }

    @Override
    public Response get(long id) { return Response.ok().build(); }

    @DELETE
    @Path("/{id}")
    public Response remove(@PathParam("id") long id) { return Response.noContent().build(); }
}
