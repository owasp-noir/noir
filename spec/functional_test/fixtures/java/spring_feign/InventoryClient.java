package com.example.inventory;

import org.springframework.cloud.openfeign.FeignClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;

import java.util.List;

@FeignClient(name = "inventory-service", url = "http://inventory-service")
public interface InventoryClient {

    @PatchMapping("/api/v2/items/{id}/stock")
    ItemResponse updateStock(
            @PathVariable("id") String itemId,
            @RequestBody StockUpdate request
    );

    @GetMapping(value = "/api/v2/items", params = "category")
    List<Item> getItemsByCategory(@RequestParam("category") String category);
}

class ItemResponse {
    public String id;
    public int stock;
}

class StockUpdate {
    public int stock;
}

class Item {
    public String id;
    public String name;
    public String category;
}
