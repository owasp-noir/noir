package com.example.api;

import javax.ws.rs.*;
import javax.ws.rs.core.MediaType;

@Path("/notes")
@Consumes(MediaType.APPLICATION_JSON)
public class NoteResource {
    @POST
    public void create(final Note note) { }
}
