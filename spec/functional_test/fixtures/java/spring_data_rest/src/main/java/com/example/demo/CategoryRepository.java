package com.example.demo;

import java.util.List;
import java.util.Optional;
import org.springframework.data.repository.Repository;

// Read-only: only the declared finders are exported.
public interface CategoryRepository extends Repository<Category, Long> {
  List<Category> findAll();

  Optional<Category> findById(Long id);

  long countByName(String name);
}
