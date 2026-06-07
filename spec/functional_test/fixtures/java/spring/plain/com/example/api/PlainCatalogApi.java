package com.plain.api;

import org.springframework.web.bind.annotation.GetMapping;

public interface PlainCatalogApi {
    @GetMapping("/items")
    String list();
}
