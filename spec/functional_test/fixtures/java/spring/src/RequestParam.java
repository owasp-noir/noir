package com.test;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class MyController {

    @GetMapping("/greet2")
    public String greet2(@RequestParam("myname") String a, @RequestParam("b") int b, String name) {
        return "Hello, " + a + b + "!";
    }
}
