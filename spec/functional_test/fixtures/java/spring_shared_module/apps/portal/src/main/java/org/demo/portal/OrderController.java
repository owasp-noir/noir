package org.demo.portal;

import org.demo.kit.NoteForm;
import org.demo.shared.model.OrderForm;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
public class OrderController implements RelayApiSpec {
    @PostMapping("/orders")
    public String create(@RequestBody OrderForm f) { return "ok"; }

    @GetMapping("/orders/search")
    public String search(OrderForm f) { return "ok"; }

    @PostMapping("/notes")
    public String note(@RequestBody NoteForm f) { return "ok"; }

    @GetMapping("/hop")
    public String relay(@RequestHeader(value = RELAY_HEADER, required = false) String origin) { return origin; }

    @GetMapping("/unresolved")
    public String unresolved(@RequestHeader(Missing.HDR) String m, @RequestParam(value = NOPE) String n) { return m; }
}
