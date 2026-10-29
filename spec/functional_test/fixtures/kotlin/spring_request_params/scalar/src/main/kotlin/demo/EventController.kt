package demo

import org.springframework.web.bind.annotation.*

data class EventRequest(val userId: String)

@RestController
class EventController {
    @PostMapping("/events/{id}")
    fun create(type: String, @PathVariable id: String, @RequestBody req: EventRequest): String = "ok"
}
