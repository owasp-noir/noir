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

@RestController
@org.springframework.web.bind.annotation.RequestMapping(ExternalPaths.BASE)
class ExternalController {
    @GetMapping("/external")
    public String external() { return "ok"; }
}


@RestController
@org.springframework.web.bind.annotation.RequestMapping("/choice")
class ChoiceController {
    @GetMapping(ExternalPaths.LEGACY ? "/v1" : "/v2")
    public String choose() { return "ok"; }
}
