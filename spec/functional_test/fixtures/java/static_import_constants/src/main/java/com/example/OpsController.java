package com.example;

import static com.example.Commons.ADMIN_CONTEXT;
import static com.example.Commons.VERSION;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

// The bare ADMIN_CONTEXT only exists through the static import; the class
// prefix must come out as /api/admin/ops, not a root-relative /raft. The
// method-level VERSION is a static import too (it used to drop the route).
@RestController
@RequestMapping(ADMIN_CONTEXT + "/ops")
public class OpsController {
    @PostMapping("/raft")
    public String raft() {
        return "ok";
    }

    @GetMapping(VERSION)
    public String version() {
        return "1";
    }
}
