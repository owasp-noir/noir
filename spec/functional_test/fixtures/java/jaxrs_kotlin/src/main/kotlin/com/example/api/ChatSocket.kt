package com.example.api

import jakarta.websocket.OnMessage
import jakarta.websocket.server.ServerEndpoint

@ServerEndpoint("/chat/{room}")
class ChatSocket {
    @OnMessage
    fun onMessage(message: String): String = message
}
