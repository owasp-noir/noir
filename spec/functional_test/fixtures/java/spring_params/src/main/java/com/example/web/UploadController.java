package com.example.web;

import java.util.List;
import lombok.Getter;
import lombok.Setter;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

@Getter
@Setter
class WidgetForm {
    String label;
    Integer weight;
}

@RestController
class UploadController {
    @PostMapping("/avatar")
    String upload(@RequestParam("img") MultipartFile img, @RequestParam("label") String l) { return "x"; }

    @PostMapping("/avatar2")
    String upload2(MultipartFile img) { return "x"; }

    @PostMapping(value = "/upload", consumes = "multipart/form-data")
    void upload(@RequestPart("meta") WidgetForm meta, @RequestPart(value = "blob", required = false) MultipartFile blob) {}

    @PutMapping("/upload")
    void reupload(@RequestPart WidgetForm meta, @RequestPart(required = false) List<MultipartFile> blobs) {}
}
