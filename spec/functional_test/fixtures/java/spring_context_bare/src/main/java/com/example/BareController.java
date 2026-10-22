package com.example;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

// No class-level @RequestMapping. The route extractor defaults an unmapped
// class to an empty prefix, so the servlet context path is the only thing
// on the left of the join — the case `File.join` composed as "/portal/".
@RestController
public class BareController {
    // Bare @GetMapping with no path argument: resolves to the context path
    // itself. Spring serves this at /portal, not /portal/.
    @GetMapping
    public String root() {
        return "ok";
    }

    // Path argument without a leading slash.
    @PostMapping("users")
    public String users() {
        return "ok";
    }
}
