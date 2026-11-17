package demo;

import org.springframework.data.domain.Pageable;
import org.springframework.web.bind.annotation.*;

@RestController
public class GizmoController {
    @GetMapping("/gizmos/search")
    public String search(@ModelAttribute GizmoSearch search, Pageable pageable) { return "ok"; }
}
