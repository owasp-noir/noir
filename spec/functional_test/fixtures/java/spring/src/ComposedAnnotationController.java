package com.test;

import org.springframework.web.bind.annotation.*;

@RequestMapping("/internal")
@interface InternalApi {
}

@GetMapping("/reports")
@interface ReportsGet {
}

@RequestMapping(method = RequestMethod.POST)
@interface JsonPost {
    String value() default "";
}

@RestController
@InternalApi
public class ComposedAnnotationController {
    @ReportsGet
    public String listReports() {
        return "";
    }

    @JsonPost("/submit")
    public String submitReport() {
        return "";
    }
}
