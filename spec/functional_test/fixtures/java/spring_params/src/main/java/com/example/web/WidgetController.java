package com.example.web;

import com.example.security.CurrentMember;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/widgets")
public class WidgetController {
    @GetMapping("/mine")
    public String mine(@CurrentMember Long memberId) { return "x"; }
}
