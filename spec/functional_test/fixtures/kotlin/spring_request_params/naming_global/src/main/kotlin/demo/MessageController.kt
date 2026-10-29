package demo

import org.springframework.web.bind.annotation.*

data class MessageRequest(
    val firstName: String,
    val orderId: Long,
)

@RestController
class MessageController {
    @PostMapping("/messages/global")
    fun send(@RequestBody req: MessageRequest): String = "ok"
}
