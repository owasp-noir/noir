package com.plain.controller;

import com.plain.api.PlainCatalogApi;
import com.plain.annotations.PlainAuditGet;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/plain")
public class PlainCatalogController implements PlainCatalogApi {
    @Override
    public String list() {
        return "plain";
    }

    @PlainAuditGet
    public String audit() {
        return "audit";
    }
}
