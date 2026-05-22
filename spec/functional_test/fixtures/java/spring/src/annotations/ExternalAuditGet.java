package com.test.annotations;

import org.springframework.web.bind.annotation.*;

@GetMapping("/audit")
public @interface ExternalAuditGet {
}
