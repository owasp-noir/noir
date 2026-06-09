package com.example;

import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/b")
public class CatalogController implements CatalogApi {
    @Override
    public String list() {
        return "b";
    }
}
