package com.test;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;

// API-first contract: the route lives on the interface (springdoc /
// OpenAPI style); the behaviour lives on the @Override below.
@RequestMapping("/api/catalog")
public interface CatalogApi {
    @GetMapping("/{id}")
    String getItem(@PathVariable String id);
}
