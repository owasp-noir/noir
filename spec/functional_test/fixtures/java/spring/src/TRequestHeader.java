package com.test;
import javax.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.http.HttpHeaders;

@RestController
@RequestMapping("/request/header")
public class TRequestHeader {

    @GetMapping
    public String greet(HttpServletRequest request, @RequestHeader(name = HttpHeaders.AUTHORIZATION) String auth) {
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
