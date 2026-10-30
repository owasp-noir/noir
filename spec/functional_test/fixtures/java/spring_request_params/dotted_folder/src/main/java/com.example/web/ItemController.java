package com.example.web;

import com.example.model.PublicItemRequest;
import com.example.dto.*;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/items")
public class ItemController {
    @PutMapping
    public String replace(@RequestBody PublicItemRequest request) { return "ok"; }

    @PostMapping
    public String create(@RequestBody CreateItemRequest request) { return "ok"; }
}
