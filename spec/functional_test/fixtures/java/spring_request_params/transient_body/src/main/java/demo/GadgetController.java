package demo;

import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/gadgets")
public class GadgetController {
    @PostMapping
    public String create(@RequestBody GadgetForm form) { return "ok"; }

    @GetMapping
    public String filter(@ModelAttribute GadgetForm form) { return "ok"; }
}
