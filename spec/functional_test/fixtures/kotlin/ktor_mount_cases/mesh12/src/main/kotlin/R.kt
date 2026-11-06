package app
import io.ktor.server.routing.*
fun Application.m() {
  routing { route("/root") { f0() } }
}
fun Route.f0() {
    get("/x0") { call.respondText("ok") }
    route("/k1") { f1() }
    route("/k2") { f2() }
    route("/k3") { f3() }
    route("/k4") { f4() }
    route("/k5") { f5() }
    route("/k6") { f6() }
    route("/k7") { f7() }
    route("/k8") { f8() }
    route("/k9") { f9() }
    route("/k10") { f10() }
    route("/k11") { f11() }
}
fun Route.f1() {
    get("/x1") { call.respondText("ok") }
    route("/k0") { f0() }
    route("/k2") { f2() }
    route("/k3") { f3() }
    route("/k4") { f4() }
    route("/k5") { f5() }
    route("/k6") { f6() }
    route("/k7") { f7() }
    route("/k8") { f8() }
    route("/k9") { f9() }
    route("/k10") { f10() }
    route("/k11") { f11() }
}
fun Route.f2() {
    get("/x2") { call.respondText("ok") }
    route("/k0") { f0() }
    route("/k1") { f1() }
    route("/k3") { f3() }
    route("/k4") { f4() }
    route("/k5") { f5() }
    route("/k6") { f6() }
    route("/k7") { f7() }
    route("/k8") { f8() }
    route("/k9") { f9() }
    route("/k10") { f10() }
    route("/k11") { f11() }
}
fun Route.f3() {
    get("/x3") { call.respondText("ok") }
    route("/k0") { f0() }
    route("/k1") { f1() }
    route("/k2") { f2() }
    route("/k4") { f4() }
    route("/k5") { f5() }
    route("/k6") { f6() }
    route("/k7") { f7() }
    route("/k8") { f8() }
    route("/k9") { f9() }
    route("/k10") { f10() }
    route("/k11") { f11() }
}
fun Route.f4() {
    get("/x4") { call.respondText("ok") }
    route("/k0") { f0() }
    route("/k1") { f1() }
    route("/k2") { f2() }
    route("/k3") { f3() }
    route("/k5") { f5() }
    route("/k6") { f6() }
    route("/k7") { f7() }
    route("/k8") { f8() }
    route("/k9") { f9() }
    route("/k10") { f10() }
    route("/k11") { f11() }
}
fun Route.f5() {
    get("/x5") { call.respondText("ok") }
    route("/k0") { f0() }
    route("/k1") { f1() }
    route("/k2") { f2() }
    route("/k3") { f3() }
    route("/k4") { f4() }
    route("/k6") { f6() }
    route("/k7") { f7() }
    route("/k8") { f8() }
    route("/k9") { f9() }
    route("/k10") { f10() }
    route("/k11") { f11() }
}
fun Route.f6() {
    get("/x6") { call.respondText("ok") }
    route("/k0") { f0() }
    route("/k1") { f1() }
    route("/k2") { f2() }
    route("/k3") { f3() }
    route("/k4") { f4() }
    route("/k5") { f5() }
    route("/k7") { f7() }
    route("/k8") { f8() }
    route("/k9") { f9() }
    route("/k10") { f10() }
    route("/k11") { f11() }
}
fun Route.f7() {
    get("/x7") { call.respondText("ok") }
    route("/k0") { f0() }
    route("/k1") { f1() }
    route("/k2") { f2() }
    route("/k3") { f3() }
    route("/k4") { f4() }
    route("/k5") { f5() }
    route("/k6") { f6() }
    route("/k8") { f8() }
    route("/k9") { f9() }
    route("/k10") { f10() }
    route("/k11") { f11() }
}
fun Route.f8() {
    get("/x8") { call.respondText("ok") }
    route("/k0") { f0() }
    route("/k1") { f1() }
    route("/k2") { f2() }
    route("/k3") { f3() }
    route("/k4") { f4() }
    route("/k5") { f5() }
    route("/k6") { f6() }
    route("/k7") { f7() }
    route("/k9") { f9() }
    route("/k10") { f10() }
    route("/k11") { f11() }
}
fun Route.f9() {
    get("/x9") { call.respondText("ok") }
    route("/k0") { f0() }
    route("/k1") { f1() }
    route("/k2") { f2() }
    route("/k3") { f3() }
    route("/k4") { f4() }
    route("/k5") { f5() }
    route("/k6") { f6() }
    route("/k7") { f7() }
    route("/k8") { f8() }
    route("/k10") { f10() }
    route("/k11") { f11() }
}
fun Route.f10() {
    get("/x10") { call.respondText("ok") }
    route("/k0") { f0() }
    route("/k1") { f1() }
    route("/k2") { f2() }
    route("/k3") { f3() }
    route("/k4") { f4() }
    route("/k5") { f5() }
    route("/k6") { f6() }
    route("/k7") { f7() }
    route("/k8") { f8() }
    route("/k9") { f9() }
    route("/k11") { f11() }
}
fun Route.f11() {
    get("/x11") { call.respondText("ok") }
    route("/k0") { f0() }
    route("/k1") { f1() }
    route("/k2") { f2() }
    route("/k3") { f3() }
    route("/k4") { f4() }
    route("/k5") { f5() }
    route("/k6") { f6() }
    route("/k7") { f7() }
    route("/k8") { f8() }
    route("/k9") { f9() }
    route("/k10") { f10() }
}