package com.example;

import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.SubscribeMapping;
import org.springframework.stereotype.Controller;

@Controller
@MessageMapping(ChatMessageController.CHAT_ROOT)
public class ChatMessageController {
    static final String CHAT_ROOT = "/chat";
    static final String SEND_PATH = "/send";

    @MessageMapping(SEND_PATH + "/{roomId}")
    public void send(ChatMessage payload) {
    }

    @SubscribeMapping("/presence/{roomId}")
    public ChatMessage presence() {
        return new ChatMessage();
    }

    static class ChatMessage {
        public String text;
    }
}
