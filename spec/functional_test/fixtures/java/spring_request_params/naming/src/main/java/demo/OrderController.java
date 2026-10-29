package demo;

import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.fasterxml.jackson.databind.annotation.JsonNaming;
import org.springframework.web.bind.annotation.*;

@RestController
public class OrderController {
    @PostMapping("/orders")
    public String create(@RequestBody OrderRequest request) { return "ok"; }
}

@JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
class OrderRequest {
    public long userId;
    public String shippingAddress;
}
