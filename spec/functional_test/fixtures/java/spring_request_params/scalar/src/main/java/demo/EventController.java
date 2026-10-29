package demo;

import org.springframework.web.bind.annotation.*;

@RestController
public class EventController {
    @PostMapping("/events/{id}")
    public String create(String type, @PathVariable String id, @RequestBody Ev req) { return "ok"; }
}

class Ev { public String userId; }
