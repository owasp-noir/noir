package com.test;

import org.springframework.web.bind.annotation.RestController;

@RestController
public class CatalogApiController implements CatalogApi {
    @Override
    public String getItem(String id) {
        catalogService.load(id);
        return AuditLog.write("get");
    }
}
