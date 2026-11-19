package com.acme.api;

import jakarta.ws.rs.*;
import java.util.List;

@Path("/pets")
public interface PetsApi {
    @GET
    @Produces({ "application/json" })
    List<Pet> listPets(@QueryParam("limit") Integer limit);

    @POST
    @Consumes({ "application/json" })
    Pet createPet(Pet pet);

    @GET
    @Path("/{petId}")
    Pet showPetById(@PathParam("petId") String petId);
}
