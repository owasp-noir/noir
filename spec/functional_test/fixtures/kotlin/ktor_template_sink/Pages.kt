import io.ktor.server.application.*
import io.ktor.server.freemarker.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Application.pages() {
    routing {
        get("/index") {
            call.respond(FreeMarkerContent("index.ftl", mapOf("name" to "x")))
        }
        get("/built") {
            val page = FreeMarkerContent("built.ftl", emptyMap<String, Any>())
            call.respond(page)
        }
    }
}
