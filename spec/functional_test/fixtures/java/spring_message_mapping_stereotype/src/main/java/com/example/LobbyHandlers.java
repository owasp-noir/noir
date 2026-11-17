package com.example;

import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.SubscribeMapping;

@SocketController
public class LobbyHandlers {
    @MessageMapping("/lobby")
    public void lobby(String text) {
    }
}

@Realtime
class PresenceHandlers {
    @SubscribeMapping("/presence")
    public String presence() {
        return "online";
    }
}
