package com.acme;

import java.util.List;
import org.springframework.http.HttpEntity;
import org.springframework.http.RequestEntity;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/java/orders")
public class OrderController {
    @PostMapping("/control")
    public String control(@RequestBody OrderLine line) { return "x"; }

    @PostMapping("/control-list")
    public String controlList(@RequestBody List<OrderLine> lines) { return "x"; }

    // Spring WebFlux reference, "@RequestBody": `handle(@RequestBody Mono<Account> account)`.
    @PostMapping("/mono")
    public Mono<String> mono(@RequestBody Mono<OrderLine> line) { return Mono.just("x"); }

    @PostMapping("/flux")
    public Mono<String> flux(@RequestBody Flux<OrderLine> lines) { return Mono.just("x"); }

    // Spring MVC reference, "HttpEntity": same as @RequestBody plus headers.
    @PostMapping("/http-entity")
    public String httpEntity(HttpEntity<OrderLine> entity) { return "x"; }

    @PostMapping("/request-entity")
    public String requestEntity(RequestEntity<OrderLine> entity) { return "x"; }
}
