package com.test;

import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.service.annotation.GetExchange;
import org.springframework.web.service.annotation.HttpExchange;

@HttpExchange("/api/v3/items")
public interface InventoryHttpClient {
    @GetExchange("/{id}/availability")
    Availability availability(
        @PathVariable("id") String itemId,
        @RequestParam("region") String region
    );

    @HttpExchange(method = "POST", url = "/bulk")
    BulkResponse bulk(@RequestParam("tenant") String tenant);
}

class Availability {
    String status;
}

class BulkResponse {
    String status;
}
