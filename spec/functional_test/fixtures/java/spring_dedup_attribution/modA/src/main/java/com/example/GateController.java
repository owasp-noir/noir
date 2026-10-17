package com.example;

import org.springframework.web.bind.annotation.*;

@RestController
public class GateController {
    @RequestMapping(value = "/gate/reset", method = RequestMethod.GET)
    public String plain() { return "plain"; }

    @RequestMapping(value = "/gate/reset", method = RequestMethod.GET, params = "ticket")
    public String t(@RequestParam("ticket") String t) { return t; }

    @RequestMapping(value = "/gate/reset", method = RequestMethod.GET, params = "relink")
    public String r(@RequestParam("relink") String r) { return r; }

    @RequestMapping("/")
    public String home(@RequestParam(value = "banner", required = false) String b) { return "home"; }
}
