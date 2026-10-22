package generated

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RestController

// Real build output next to build.gradle.kts: must stay pruned.
@RestController
class GeneratedController {
    @GetMapping("/generated")
    fun generated(): String = "no"
}
