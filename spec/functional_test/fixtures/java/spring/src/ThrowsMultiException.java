package com.test;
import javax.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.http.HttpHeaders;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestHeader;

@RestController
@RequestMapping("/throws/multi/exception")
public class ThrowsMultiException {

    @GetMapping
    public String greet(HttpServletRequest request)
        throws
        InternalErrorException, IllegalParamException,
        Exception {
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
