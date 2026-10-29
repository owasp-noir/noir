package demo

import org.springframework.http.HttpHeaders
import org.springframework.web.bind.annotation.*

data class LogEntry(val message: String)

@RestController
class LogController {
    @PostMapping("/logs")
    fun log(@RequestHeader headers: HttpHeaders, @RequestBody entry: LogEntry): String = "ok"

    @GetMapping("/logs")
    fun list(@RequestHeader all: Map<String, String>): String = "ok"
}
