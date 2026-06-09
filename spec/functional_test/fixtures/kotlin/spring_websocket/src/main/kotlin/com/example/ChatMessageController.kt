package com.example

import org.springframework.messaging.handler.annotation.MessageMapping
import org.springframework.messaging.handler.annotation.SendTo
import org.springframework.messaging.handler.annotation.SubscribeMapping
import org.springframework.stereotype.Controller

@Controller
@MessageMapping(ChatMessageController.CHAT_ROOT)
class ChatMessageController(private val chatService: ChatService) {
    @MessageMapping(SEND_PATH + "/{roomId}")
    @SendTo("/topic/chat/{roomId}")
    fun send(message: ChatMessage): String {
        return chatService.send(message)
    }

    @SubscribeMapping("/presence/{roomId}")
    fun presence(): String {
        return chatService.presence()
    }

    @MessageMapping("/echo")
    @SendTo("/topic/echo")
    fun echo(message: ChatMessage): ChatMessage {
        return message
    }

    companion object {
        const val CHAT_ROOT = "/chat"
        const val SEND_PATH = "/send"
    }
}

data class ChatMessage(
    val text: String,
    val author: String
)

class ChatService {
    fun send(message: ChatMessage): String = message.text
    fun presence(): String = "online"
}
