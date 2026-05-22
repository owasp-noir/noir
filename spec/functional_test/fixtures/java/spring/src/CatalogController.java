package com.test;

import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class CatalogController implements CatalogApi {
    @Override
    public Catalog getCatalog(String id, String view) {
        return new Catalog();
    }

    @Override
    public Catalog createCatalog(Catalog catalog) {
        return catalog;
    }
}
