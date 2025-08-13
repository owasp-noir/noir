package com.test;
import org.springframework.cloud.openfeign.FeignClient;
import org.springframework.web.bind.annotation.*;

@FeignClient(name = "inventory-service", url = "...")
public interface InventoryClient {
    
    @PatchMapping("/api/v2/items/{id}/stock")
    ItemResponse updateStock(
        @PathVariable("id") String itemId,
        @RequestBody StockUpdate request
    );

    @GetMapping(value = "/api/v2/items", params = "category")
    List<Item> getItemsByCategory(@RequestParam("category") String category);

    @PostMapping("/api/v2/items")
    ItemResponse createItem(@RequestBody Item item);
    
    @DeleteMapping("/api/v2/items/{id}")
    void deleteItem(@PathVariable("id") String itemId);
}

class StockUpdate {
    int quantity;
    
    public void setQuantity(int quantity) {
        this.quantity = quantity;
    }
    
    public int getQuantity() {
        return quantity;
    }
}

class ItemResponse {
    String status;
    
    public void setStatus(String status) {
        this.status = status;
    }
    
    public String getStatus() {
        return status;
    }
}