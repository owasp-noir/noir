package com.example.api;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.container.AsyncResponse;
import jakarta.ws.rs.container.Suspended;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.jboss.resteasy.plugins.providers.multipart.MultipartFormDataInput;
import org.jboss.resteasy.reactive.RestPath;
import org.jboss.resteasy.reactive.RestQuery;
import org.jboss.resteasy.reactive.RestHeader;
import org.jboss.resteasy.reactive.RestForm;
import org.jboss.resteasy.reactive.RestCookie;

@Path("/greetings")
@Produces(MediaType.APPLICATION_JSON)
public class GreetingResource {

    @GET
    public Response list(@RestQuery("page") int page,
                         @RestQuery int size) {
        return Response.ok().build();
    }

    @GET
    @Path("/{id}")
    public Response get(@RestPath long id,
                        @RestHeader("X-Trace") String trace) {
        return Response.ok().build();
    }

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    public Response create(Greeting body) {
        return Response.status(201).build();
    }

    @POST
    @Path("/login")
    @Consumes(MediaType.APPLICATION_FORM_URLENCODED)
    public Response login(@RestForm String username,
                          @RestForm("pwd") String password,
                          RoutingContext ctx,
                          @Suspended AsyncResponse ar) {
        return Response.ok().build();
    }

    @POST
    @Path("/upload")
    @Consumes(MediaType.MULTIPART_FORM_DATA)
    public Response upload(MultipartFormDataInput data) {
        data.getFormDataMap().get("image");
        return Response.ok().build();
    }

    @PUT
    @Path("/{id}")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response update(@RestPath long id, Greeting body) {
        return Response.ok().build();
    }

    @DELETE
    @Path("/{id}")
    public Response delete(@RestPath long id,
                           @RestCookie("session") String session) {
        return Response.noContent().build();
    }
}

class RoutingContext {
}
