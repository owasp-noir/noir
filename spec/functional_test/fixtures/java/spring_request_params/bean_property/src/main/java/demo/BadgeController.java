package demo;

import lombok.Data;
import org.springframework.web.bind.annotation.*;

@RestController
public class BadgeController {
    @PostMapping("/badges")
    public String create(@RequestBody Badge badge) { return "ok"; }
}

// Lombok writes isActive()/setActive() for `boolean isActive`, so Jackson
// binds `active`; `Boolean isShared` gets setIsShared() and keeps its name.
@Data
class Badge {
    private boolean isActive;
    private Boolean isShared;
}
