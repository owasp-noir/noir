package demo;

import org.springframework.web.bind.annotation.*;

@RestController
public class ShopController {
    @GetMapping("/stores/{storeId}/widgets")
    public String widgets(@PathVariable Long storeId, ShopSession session, Long limit) { return "ok"; }

    @GetMapping("/stores/bound")
    public String bound(@ModelAttribute ShopSession session) { return "ok"; }

    @GetMapping("/tenants/current")
    public String current(@Tenant TenantRef tenant) { return "ok"; }

    @GetMapping("/tenants/lookup")
    public String lookup(TenantRef tenant) { return "ok"; }
}
