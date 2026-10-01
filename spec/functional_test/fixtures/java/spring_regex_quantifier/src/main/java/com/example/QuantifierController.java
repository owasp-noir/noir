package com.example;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

// Path-variable regex constraints with their own `{n}` quantifier. The
// placeholder ends at the matching brace, not at the quantifier's `}`.
@RestController
@RequestMapping("/api")
public class QuantifierController {
    @GetMapping("/items/{id:[0-9]{3}}")
    public String item(@PathVariable String id) {
        return id;
    }

    @GetMapping("/zip/{code:\\d{5}}/x")
    public String zip(@PathVariable String code) {
        return code;
    }
}
