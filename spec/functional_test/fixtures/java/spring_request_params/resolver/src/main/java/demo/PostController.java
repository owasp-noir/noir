package demo;

import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/posts")
public class PostController {
    @GetMapping("/{postId}")
    public String detail(@PathVariable String postId, @CurrentAccount Long accountId) { return "ok"; }
}
