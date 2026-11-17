package com.example;

import com.example.starter.StompController;
import org.springframework.messaging.handler.annotation.MessageMapping;

// @StompController comes from a starter jar outside the scan: it may carry
// @Controller, so the destination stays.
@StompController
public class ExternalHandlers {
    @MessageMapping("/external")
    public void external(String text) {
    }
}
