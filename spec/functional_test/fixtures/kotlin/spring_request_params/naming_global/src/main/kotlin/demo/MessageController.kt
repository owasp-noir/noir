package demo

import com.fasterxml.jackson.databind.PropertyNamingStrategies
import com.fasterxml.jackson.databind.annotation.JsonNaming
import org.springframework.web.bind.annotation.*

data class MessageRequest(
    val firstName: String,
    val orderId: Long,
)

// Opts this DTO out of the module-wide SNAKE_CASE default.
@JsonNaming(PropertyNamingStrategies.LowerCamelCaseStrategy::class)
data class CamelRequest(val firstName: String)

@RestController
class MessageController {
    @PostMapping("/messages/global")
    fun send(@RequestBody req: MessageRequest): String = "ok"

    @PostMapping("/messages/camel")
    fun camel(@RequestBody req: CamelRequest): String = "ok"
}
