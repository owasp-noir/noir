package app
import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.auth.*
fun Application.module() {
    routing {
        authenticate("jwt") {
            secret()
        }
        route("/r1") { crud() }
        route("/r2") { crud() }
        route("/r3") { crud() }
        route("/r4") { crud() }
        route("/r5") { crud() }
        route("/r6") { crud() }
        route("/r7") { crud() }
        route("/r8") { crud() }
        route("/r9") { crud() }
        route("/r10") { crud() }
        route("/r11") { crud() }
        route("/r12") { crud() }
        route("/r13") { crud() }
        route("/r14") { crud() }
        route("/r15") { crud() }
        route("/r16") { crud() }
        route("/r17") { crud() }
        route("/r18") { crud() }
        route("/r19") { crud() }
        route("/r20") { crud() }
    }
    Metrics.secret()
}
