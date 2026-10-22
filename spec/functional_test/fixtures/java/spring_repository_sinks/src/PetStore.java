package com.test;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

// A repository by what it extends, not by its name.
public interface PetStore extends JpaRepository<Pet, Integer> {

    @Query("SELECT t.name FROM PetType t ORDER BY t.name")
    List<String> petTypes();
}
