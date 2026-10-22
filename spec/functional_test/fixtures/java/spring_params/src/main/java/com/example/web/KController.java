package com.example.web;

import org.springframework.web.bind.annotation.*;

enum Color { RED, BLUE }

class GadgetCode {
    private final String raw;
    private GadgetCode(String raw) { this.raw = raw; }
    public static GadgetCode valueOf(String raw) { return new GadgetCode(raw); }
}

class SomeClass {
    public String q;
}

@RestController
@RequestMapping("/k")
class KController {
    @GetMapping("/a") String a(@RequestParam(required = false, name = "kind") Color w) { return "x"; }
    @GetMapping("/b") String b(@RequestParam("kind") Color w) { return "x"; }
    @GetMapping("/c") String c(@RequestParam Color kind) { return "x"; }
    @GetMapping("/d") String d(@RequestParam("code") GadgetCode code) { return "x"; }
    @GetMapping("/e") String e(@RequestParam(required = false, name = "kind") String w) { return "x"; }
    @GetMapping("/f") String f(@RequestParam("flt") SomeClass f) { return "x"; }
    @GetMapping("/g") String g(@RequestHeader("X-Color") Color c) { return "x"; }
    @GetMapping("/h") String h(@RequestParam java.util.Map<String, String> all) { return "x"; }
}
