package com.example;

import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.stereotype.Component;

// Not a @Controller: Spring's messaging handler detection never sees it.
@Component
public class RelayService {
    @MessageMapping("/relay")
    public void relay(String text) {
    }
}
