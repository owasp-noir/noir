package com.example.ws

import org.springframework.context.annotation.Configuration
import org.springframework.web.socket.config.annotation.EnableWebSocket
import org.springframework.web.socket.config.annotation.WebSocketConfigurer
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry

@Configuration
@EnableWebSocket
class WebSocketConfig(private val chatHandler: ChatHandler) : WebSocketConfigurer {
    companion object {
        const val TICKER_PATH = "/ticker"
    }

    override fun registerWebSocketHandlers(registry: WebSocketHandlerRegistry) {
        registry.addHandler(chatHandler, "/chat").setAllowedOrigins("*")
        registry.addHandler(TickerHandler(), TICKER_PATH, "/ticker/legacy").withSockJS()
        // registry.addHandler(oldHandler, "/old")
    }
}
