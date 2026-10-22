package com.example;

import static com.example.Commons.*;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

// Wildcard static import: TASKS arrives as a bare name.
@RestController
@RequestMapping(value = TASKS)
public class TaskController {
    @GetMapping("/poll/{taskType}")
    public String poll() {
        return "ok";
    }
}
