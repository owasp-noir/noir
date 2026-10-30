package demo

import com.fasterxml.jackson.annotation.JsonRootName
import com.fasterxml.jackson.databind.PropertyNamingStrategies
import com.fasterxml.jackson.databind.annotation.JsonNaming
import org.springframework.web.bind.annotation.*

// A one-line annotated class above another class annotates only itself.
@JsonRootName("a") data class Annotated(val x: String)
data class Plain(val yName: String)
@JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy::class) data class Snake(val q: String)
data class Camel(val mName: String)

// @JsonRootName("commented")
data class LineCommented(val z: String)
/* @JsonRootName("block") */
data class BlockCommented(val w: String)

@RestController
class NeighboursApi {
    @PostMapping("/plain")
    fun plain(@RequestBody p: Plain): String = "ok"

    @PostMapping("/camel")
    fun camel(@RequestBody p: Camel): String = "ok"

    @PostMapping("/line-commented")
    fun lineCommented(@RequestBody p: LineCommented): String = "ok"

    @PostMapping("/block-commented")
    fun blockCommented(@RequestBody p: BlockCommented): String = "ok"
}
