package com.test;
import javax.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class MyController {

    @GetMapping("/greet")
    public String greet(HttpServletRequest request) {
        String name = request.getParameter("name");
        if (name == null || name.isEmpty()) {
            name = "World";
        }

        String header = request.getHeader("header");
        if (header == null || header.isEmpty()) {
            header = "!";
        }
        return "Hello, " + name + header;
    }
}
