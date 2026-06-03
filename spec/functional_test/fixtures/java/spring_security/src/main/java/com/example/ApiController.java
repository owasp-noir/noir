package com.example;

import org.springframework.web.bind.annotation.*;
import javax.validation.Valid;

@RestController
@CrossOrigin(origins = "*")
@RequestMapping("/api")
public class ApiController {

    @PostMapping("/posts")
    public String createPost(@Valid @RequestBody PostDto dto) {
        return "created";
    }

    @PutMapping("/posts/{id}")
    public String updatePost(@PathVariable Long id, @RequestBody PostDto dto) {
        return "updated";
    }

    @GetMapping("/posts")
    public String listPosts() {
        return "list";
    }
}
