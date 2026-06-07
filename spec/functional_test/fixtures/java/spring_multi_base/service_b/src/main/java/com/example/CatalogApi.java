package com.example;

import org.springframework.web.bind.annotation.GetMapping;

public interface CatalogApi {
    @GetMapping("/from-b")
    String list();
}
