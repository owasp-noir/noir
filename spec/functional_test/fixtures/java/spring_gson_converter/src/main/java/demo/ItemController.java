package demo;

import lombok.Data;
import org.springframework.web.bind.annotation.*;

@RestController
public class ItemController {
    @PostMapping("/items")
    public String create(@RequestBody Item item) { return "ok"; }

    @GetMapping("/items")
    public String search(Item item) { return "ok"; }
}

@Data
class Item {
    private boolean isHidden;
    private String name;
}
