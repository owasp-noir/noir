package com.test;

import org.springframework.web.bind.annotation.*;

interface SharedRoutes {
    String V3 = "/v3";
}

// Prefix from a constant declared in another file (SharedPaths.java).
@RestController
@RequestMapping(SharedPaths.SHARED_USERS)
public class SharedPathController {
    @GetMapping("/{id}")
    public void user(@PathVariable String id) {}
}

// Interface constants, qualified and inherited through `implements`.
@RestController
class SharedRoutesController implements SharedRoutes {
    @GetMapping(V3 + "/ping")
    public String ping() { return ""; }

    @GetMapping(SharedRoutes.V3 + "/pong")
    public String pong() { return ""; }
}
