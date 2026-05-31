package com.test;

import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

// Concrete controller inheriting the base CRUD routes under `/crud`:
//   GET  /crud/list   (inherited)
//   GET  /crud/{id}   (inherited, with path param)
//   POST /crud        (own)
@RestController
@RequestMapping("/crud")
public class CrudReportController extends AbstractCrudController {
    @PostMapping
    public String create() {
        return "created";
    }
}
