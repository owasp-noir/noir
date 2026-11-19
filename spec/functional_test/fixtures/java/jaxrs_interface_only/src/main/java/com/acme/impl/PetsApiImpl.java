package com.acme.impl;

import com.acme.api.Pet;
import com.acme.api.PetsApi;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.List;

@ApplicationScoped
public class PetsApiImpl implements PetsApi {
    @Override
    public List<Pet> listPets(Integer limit) { return List.of(); }

    @Override
    public Pet createPet(Pet pet) { return pet; }

    @Override
    public Pet showPetById(String petId) { return new Pet(); }
}
