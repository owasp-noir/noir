package com.example;

import org.springframework.web.bind.annotation.*;
import org.springframework.security.access.prepost.PreAuthorize;
import javax.annotation.security.RolesAllowed;
import org.springframework.security.access.annotation.Secured;

@RestController
@RequestMapping("/api")
public class Controller {

    @PreAuthorize("hasRole('ADMIN')")
    @GetMapping("/admin/users")
    public String getUsers() {
        return "users";
    }

    @Secured("ROLE_USER")
    @PostMapping("/posts")
    public String createPost() {
        return "created";
    }

    @RolesAllowed({"ROLE_ADMIN", "ROLE_MANAGER"})
    @DeleteMapping("/posts/{id}")
    public String deletePost(@PathVariable Long id) {
        return "deleted";
    }

    @GetMapping("/closed/config")
    public String deniedByConfig() {
        return "closed";
    }

    @PreAuthorize("denyAll()")
    @GetMapping("/closed/annotation")
    public String deniedByExpression() {
        return "closed";
    }

    @DenyAll
    @GetMapping("/closed/marker")
    public String deniedByMarker() {
        return "closed";
    }
}
