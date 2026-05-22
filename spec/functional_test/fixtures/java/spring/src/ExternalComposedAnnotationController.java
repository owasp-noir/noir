package com.test;

import com.test.annotations.ExternalApi;
import com.test.annotations.ExternalAuditGet;
import com.test.annotations.ExternalDelete;
import org.springframework.web.bind.annotation.RestController;

@RestController
@ExternalApi
public class ExternalComposedAnnotationController {
    @ExternalAuditGet
    public String audit() {
        return "";
    }

    @ExternalDelete("/reports/{id}")
    public void deleteReport(Long id) {
    }
}
