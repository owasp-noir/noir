package demo;

import lombok.Data;
import org.springframework.web.bind.annotation.*;

@RestController
public class FlagController {
    @PostMapping("/flags")
    public String create(@RequestBody Flag flag) { return "ok"; }

    @GetMapping("/flags")
    public String search(Flag flag) { return "ok"; }
}

// Gson reads JSON by field name (`isPinned`); form binding still goes
// through the bean property (`pinned`).
@Data
class Flag {
    private boolean isPinned;
    private String label;
}
