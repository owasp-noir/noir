package com.test;

import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;

@RequestMapping("/catalog")
public interface CatalogApi {
    @GetMapping("/{id}")
    Catalog getCatalog(@PathVariable("id") String id, @RequestParam("view") String view);

    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE)
    Catalog createCatalog(@RequestBody Catalog catalog);
}

class Catalog {
    private String title;
    private int count;

    public void setTitle(String title) {
        this.title = title;
    }

    public void setCount(int count) {
        this.count = count;
    }
}
