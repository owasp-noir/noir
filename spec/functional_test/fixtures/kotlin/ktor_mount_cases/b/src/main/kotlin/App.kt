package app
import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.auth.*

fun Application.module() {
    val svc = UserService()
    routing {
        route("/api") {
            authenticate("jwt") {
                users()
            }
        }
        authenticate("jwt") {
            with(AdminController()) { routes() }
        }
        with(PublicController()) { routes() }
        authenticate("jwt") {
            this@routing.label()
        }
        authenticate("jwt", strategy = AuthenticationStrategy.Optional) {
            maybe()
        }
    }
    svc.users()
}
class UserService { fun users(): List<String> = listOf() }
