package demo;

import org.springframework.security.access.annotation.Secured;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class PublicController {
    @GetMapping("/public/a")
    @PreAuthorize("permitAll()")
    public String a() { return "a"; }

    @GetMapping("/public/b")
    @Secured("IS_AUTHENTICATED_ANONYMOUSLY")
    public String b() { return "b"; }

    @GetMapping("/public/c")
    @PreAuthorize("hasRole('USER')")
    public String c() { return "c"; }

    @GetMapping("/public/d")
    @Secured("ROLE_ADMIN")
    public String d() { return "d"; }

    // @PreAuthorize("hasRole('ADMIN')")
    @GetMapping("/public/e")
    public String e() { return "e"; }
}
