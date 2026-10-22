package com.example.app.services;

import com.vaadin.hilla.Endpoint;
import jakarta.annotation.security.PermitAll;
import java.util.List;

@Endpoint("orders")
@PermitAll
public class OrderService {
  public List<String> list() { return List.of(); }
}
