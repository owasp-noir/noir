package io.helidon.examples.quickstart.mp;

import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

/**
 * A simple JAX-RS resource to greet you. No Helidon import appears
 * anywhere in this file — matches Helidon's own quickstart-mp, whose
 * MP runtime is pulled in solely through `pom.xml`.
 */
@Path("/greet")
public class GreetResource {

    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public GreetingMessage getDefaultMessage(@QueryParam("lang") String lang) {
        return new GreetingMessage("Hello " + lang);
    }

    @Path("/{name}")
    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public GreetingMessage getMessage(@PathParam("name") String name,
                                      @HeaderParam("X-Trace-Id") String traceId) {
        return new GreetingMessage(name);
    }

    @Path("/greeting")
    @PUT
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Response updateGreeting(GreetingMessage message) {
        return Response.status(Response.Status.NO_CONTENT).build();
    }
}
