package com.example.demo;

import java.util.List;
import org.springframework.data.domain.Pageable;
import org.springframework.data.repository.CrudRepository;
import org.springframework.data.repository.query.Param;
import org.springframework.data.rest.core.annotation.RestResource;

// No annotation: exported by default at the pluralized entity name.
public interface OrderRepository extends CrudRepository<Order, Long> {
  @Override
  @RestResource(exported = false)
  void deleteById(Long id);

  @RestResource(path = "byStatus")
  List<Order> findByStatus(@Param("status") String status, Pageable pageable);

  @RestResource(exported = false)
  List<Order> findByInternalNote(String note);
}
