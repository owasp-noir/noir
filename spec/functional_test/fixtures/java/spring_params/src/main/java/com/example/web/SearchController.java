package com.example.web;

import lombok.Setter;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

@Setter
class Pager {
    Integer offset;
    Integer limit;
}

@Setter
class Tag {
    String name;
}

@Setter
class Filter {
    String keyword;
    Pager pager;
    Tag tag;
    MultipartFile[] uploads;
}

@RestController
class SearchController {
    @GetMapping("/search") String search(Filter f) { return "x"; }
    @PostMapping("/save") String save(@RequestParam("payload") String p, Filter f) { return "x"; }
    @PostMapping("/save2") String save2(Filter f) { return "x"; }
}
