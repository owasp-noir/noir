package shop
import io.ktor.server.application.*
import io.ktor.server.routing.*
fun validate(o: Order) { require(o.qty > 0) }
fun Application.shop() {
    routing {
        post("/orders") {
            val o = call.receive<Order>()
            validate(o)
            call.respondText("ok")
        }
    }
}
