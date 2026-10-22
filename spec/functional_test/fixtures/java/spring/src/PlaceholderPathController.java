package com.test;

import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("${api.base.path:/api}")
public class PlaceholderPathController {

    @GetMapping("/items")
    public String listItems() {
        return "items";
    }

    @GetMapping("${app.docs.path:/docs}/guide")
    public String docsGuide() {
        return "guide";
    }
}

@Controller
@RequestMapping("${server.error.path:${error.path:/error}}")
class BasicErrorController {

    @RequestMapping
    public ResponseEntity<String> error() {
        return ResponseEntity.ok("error");
    }
}
