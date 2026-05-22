package com.example.api;

import jakarta.websocket.OnMessage;
import jakarta.websocket.Session;
import jakarta.websocket.server.PathParam;
import jakarta.websocket.server.ServerEndpoint;

@ServerEndpoint(ChatSocket.API_ROOT + "/chat/{roomId}/{username}")
public class ChatSocket {
    static final String API_ROOT = "/ws";

    @OnMessage
    public void message(String message,
                        @PathParam("roomId") String roomId,
                        @PathParam("username") String username,
                        Session session) {
    }
}
