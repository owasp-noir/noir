package demo

import com.fasterxml.jackson.databind.PropertyNamingStrategies
import com.fasterxml.jackson.databind.annotation.JsonNaming
import com.fasterxml.jackson.annotation.JsonProperty
import org.springframework.web.bind.annotation.*

@JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy::class)
data class MessageRequest(
    val firstName: String,
    val orderId: Long,
    @JsonProperty("NOTE") val noteText: String,
)

@RestController
class MessageController {
    @PostMapping("/messages")
    fun send(@RequestBody req: MessageRequest): String = "ok"
}
