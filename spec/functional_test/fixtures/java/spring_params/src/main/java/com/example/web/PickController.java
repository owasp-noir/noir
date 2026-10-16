package com.example.web;

import javax.servlet.http.HttpServletRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableDefault;
import org.springframework.web.bind.annotation.*;

@RestController
class PickController {
    @PostMapping("/pick/{slot}")
    String pick(HttpServletRequest request, @PathVariable("slot") Long slot) {
        request.getHeader("X-Back");
        request.getParameter("flavor");
        return "x";
    }

    @PostMapping("/pick2")
    String pick2(@RequestParam("a") String a, HttpServletRequest request) {
        request.getParameter("flavor");
        return "x";
    }

    @GetMapping("/paged")
    String paged(@RequestParam String q, Pageable pageable) { return "x"; }

    @GetMapping("/paged2")
    String paged2(@PageableDefault(size = 20, sort = "id") Pageable pageable) { return "x"; }
}
