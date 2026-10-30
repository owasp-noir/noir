package com.example.ws;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

@Configuration
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {
    private static final String TICKER_PATH = "/ticker";
    private final ChatHandler chatHandler;
    public WebSocketConfig(ChatHandler chatHandler) { this.chatHandler = chatHandler; }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler(chatHandler, "/chat").setAllowedOrigins("*");
        registry.addHandler(new TickerHandler(), TICKER_PATH, "/ticker/legacy").withSockJS();
        // registry.addHandler(oldHandler, "/old");
        registry.addHandler(quotesHandler(), "/quotes-live").setAllowedOrigins("*");
        registry.addHandler(new BulletinHandler(), "/bulletin")
            .setAllowedOriginPatterns("*");
        registry.addHandler(new BulletinHandler(), "/bulletinboard");
    }
}
