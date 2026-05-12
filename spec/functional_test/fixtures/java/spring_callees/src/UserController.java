package com.test;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/users")
public class UserController {

    private final UserService service;

    public UserController(UserService service) {
        this.service = service;
    }

    @PostMapping("/")
    public String createUser() {
        String saved = service.save("hahwul");
        AuditLog.write(saved);
        return saved;
    }

    @GetMapping("/profile")
    public String profile() {
        String built = this.buildProfile();
        AuditLog.write(built);
        return built;
    }

    private String buildProfile() {
        return "profile";
    }
}
