package com.example;

import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class RedirectController {
    @GetMapping("/out")
    public void out(@RequestParam String next, HttpServletResponse response) throws IOException {
        response.sendRedirect(next);
    }

    @GetMapping("/go")
    public String go(@RequestParam String next) {
        return "redirect:" + next;
    }

    @GetMapping("/status")
    public void status(HttpServletResponse response) throws IOException {
        response.sendError(204);
    }
}
