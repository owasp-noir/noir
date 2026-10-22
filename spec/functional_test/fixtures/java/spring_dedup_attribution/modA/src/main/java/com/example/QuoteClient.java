package com.example;

import org.springframework.cloud.openfeign.FeignClient;
import org.springframework.web.bind.annotation.*;

@FeignClient(name = "upstream", url = "${up.url}")
public interface QuoteClient {
    @GetMapping("/v1/quote")
    String quote(@RequestParam("ticker") String t);
}
