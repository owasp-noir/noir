package com.test;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

    @GetMapping("/legacy")
    public String legacy() {
        AuditLog.write("legacy");
        return getLegacy().toString();
    }

    private String getLegacy() {
        return "legacy";
    }
}
