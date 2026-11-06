package app
import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.auth.*

fun Application.module() {
    routing {
        route("/p") { a() }
        authenticate("jwt") {
            val s = """
              } } } ) authenticate {
            """
            route("/q") { b() }
        }
        // 한글 주석 } }
        route("/한글") { c() }
        route("/pd") { d() }
        route("/pe") { e() }
        authenticate("jwt") { route("/g1") { f() } }; route("/g2") { f2() }
    }
}
