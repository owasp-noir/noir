package com.example

import io.micronaut.websocket.annotation.OnMessage
import io.micronaut.websocket.annotation.ServerWebSocket

@ServerWebSocket("/ws/books/{topic}")
class BookSocket {
    @OnMessage
    fun onMessage(topic: String, message: String): String = message
}
