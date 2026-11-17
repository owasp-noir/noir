package com.example;

import com.example.starter.CompanyController;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;

// @CompanyController comes from a starter jar outside the scan: it may well
// be meta-annotated with @RestController, so the class may be a controller.
@CompanyController
@RequestMapping("/api/payments")
public class PaymentEndpoint {
    @GetMapping("/list")
    public String list() {
        return "[]";
    }
}
