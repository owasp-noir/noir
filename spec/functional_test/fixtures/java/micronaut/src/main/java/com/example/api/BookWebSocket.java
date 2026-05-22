package com.example.api;

import io.micronaut.websocket.WebSocketSession;
import io.micronaut.websocket.annotation.OnMessage;
import io.micronaut.websocket.annotation.OnOpen;
import io.micronaut.websocket.annotation.ServerWebSocket;

@ServerWebSocket(BookWebSocket.API_ROOT + "/books/ws/{topic}/{username}")
public class BookWebSocket {
    static final String API_ROOT = "/api";

    @OnOpen
    public void open(String topic, String username, WebSocketSession session) {
    }

    @OnMessage
    public void message(String topic, String username, String message, WebSocketSession session) {
    }
}
