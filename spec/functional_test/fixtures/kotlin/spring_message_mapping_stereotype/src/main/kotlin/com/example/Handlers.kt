package com.example

import org.springframework.messaging.handler.annotation.MessageMapping
import org.springframework.stereotype.Component
import org.springframework.stereotype.Controller

@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
@Controller
annotation class SocketController

@Controller
class ChatController {
    @MessageMapping("/chat")
    fun chat(text: String) {
    }
}

@SocketController
class LobbyHandlers {
    @MessageMapping("/lobby")
    fun lobby(text: String) {
    }
}

@Controller
abstract class BaseHandlers

// @Controller on the superclass: Spring finds it up the hierarchy.
class ScoreHandlers : BaseHandlers() {
    @MessageMapping("/score")
    fun score(text: String) {
    }
}

// Not a @Controller: Spring's messaging handler detection never sees it.
@Component
class RelayService {
    @MessageMapping("/relay")
    fun relay(text: String) {
    }
}
