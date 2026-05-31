package com.test;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;

// Abstract base controller: never mapped on its own, so `/list` and
// `/{id}` must NOT surface without a concrete subclass prefix. The
// routes only exist through CrudReportController below.
public abstract class AbstractCrudController {
    @GetMapping("/list")
    public String list() {
        return "list";
    }

    @GetMapping("/{id}")
    public String get(@PathVariable("id") String id) {
        return id;
    }
}
