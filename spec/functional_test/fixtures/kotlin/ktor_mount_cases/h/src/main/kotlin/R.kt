package app
import io.ktor.server.routing.*

fun Route.a() {
    val doc = """
    fun Route.z() {
    """
    get("/a") { call.respondText("é } ü") }
    route("/n") {
        listOf(1).forEach { _ -> get("/lam") { call.respondText("x") } }
    }
}
fun Route.b() { get("/b") { call.respondText("x") } }
fun Route.c() {
    get("/c") { call.respondText("日本語") }
}
fun Route.d() { get("/d") { call.respondText("x") } }; fun Route.e() { get("/e") { call.respondText("x") } }
fun Route.f() { get("/f") { call.respondText("x") } }
fun Route.f2() { get("/f2") { call.respondText("x") } }
