package com.test;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

public interface OwnerRepository extends JpaRepository<Owner, Integer> {

    Page<Owner> findByLastNameStartingWith(String lastName, Pageable pageable);
}
