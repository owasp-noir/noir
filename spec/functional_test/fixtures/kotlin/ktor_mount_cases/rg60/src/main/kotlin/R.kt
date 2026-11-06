package app
import io.ktor.server.routing.*
fun Application.m() {
  routing { route("/root") { f0() } }
}
fun Route.f0() {
    get("/x0") { call.respondText("ok") }
    route("/k9") { f9() }
    route("/k37") { f37() }
    route("/k55") { f55() }
}
fun Route.f1() {
    get("/x1") { call.respondText("ok") }
    route("/k52") { f52() }
    route("/k49") { f49() }
    route("/k5") { f5() }
}
fun Route.f2() {
    get("/x2") { call.respondText("ok") }
    route("/k17") { f17() }
    route("/k8") { f8() }
    route("/k32") { f32() }
}
fun Route.f3() {
    get("/x3") { call.respondText("ok") }
    route("/k49") { f49() }
    route("/k29") { f29() }
    route("/k31") { f31() }
}
fun Route.f4() {
    get("/x4") { call.respondText("ok") }
    route("/k42") { f42() }
    route("/k25") { f25() }
    route("/k51") { f51() }
}
fun Route.f5() {
    get("/x5") { call.respondText("ok") }
    route("/k14") { f14() }
    route("/k7") { f7() }
    route("/k32") { f32() }
}
fun Route.f6() {
    get("/x6") { call.respondText("ok") }
    route("/k1") { f1() }
    route("/k58") { f58() }
    route("/k54") { f54() }
}
fun Route.f7() {
    get("/x7") { call.respondText("ok") }
    route("/k25") { f25() }
    route("/k28") { f28() }
    route("/k39") { f39() }
}
fun Route.f8() {
    get("/x8") { call.respondText("ok") }
    route("/k49") { f49() }
    route("/k50") { f50() }
    route("/k0") { f0() }
}
fun Route.f9() {
    get("/x9") { call.respondText("ok") }
    route("/k45") { f45() }
    route("/k29") { f29() }
    route("/k18") { f18() }
}
fun Route.f10() {
    get("/x10") { call.respondText("ok") }
    route("/k47") { f47() }
    route("/k52") { f52() }
    route("/k15") { f15() }
}
fun Route.f11() {
    get("/x11") { call.respondText("ok") }
    route("/k38") { f38() }
    route("/k6") { f6() }
    route("/k58") { f58() }
}
fun Route.f12() {
    get("/x12") { call.respondText("ok") }
    route("/k21") { f21() }
    route("/k1") { f1() }
    route("/k42") { f42() }
}
fun Route.f13() {
    get("/x13") { call.respondText("ok") }
    route("/k35") { f35() }
    route("/k0") { f0() }
    route("/k57") { f57() }
}
fun Route.f14() {
    get("/x14") { call.respondText("ok") }
    route("/k25") { f25() }
    route("/k44") { f44() }
    route("/k13") { f13() }
}
fun Route.f15() {
    get("/x15") { call.respondText("ok") }
    route("/k28") { f28() }
    route("/k47") { f47() }
    route("/k1") { f1() }
}
fun Route.f16() {
    get("/x16") { call.respondText("ok") }
    route("/k34") { f34() }
    route("/k14") { f14() }
    route("/k49") { f49() }
}
fun Route.f17() {
    get("/x17") { call.respondText("ok") }
    route("/k29") { f29() }
    route("/k32") { f32() }
    route("/k36") { f36() }
}
fun Route.f18() {
    get("/x18") { call.respondText("ok") }
    route("/k14") { f14() }
    route("/k23") { f23() }
    route("/k44") { f44() }
}
fun Route.f19() {
    get("/x19") { call.respondText("ok") }
    route("/k14") { f14() }
    route("/k49") { f49() }
    route("/k30") { f30() }
}
fun Route.f20() {
    get("/x20") { call.respondText("ok") }
    route("/k18") { f18() }
    route("/k1") { f1() }
    route("/k27") { f27() }
}
fun Route.f21() {
    get("/x21") { call.respondText("ok") }
    route("/k54") { f54() }
    route("/k59") { f59() }
    route("/k36") { f36() }
}
fun Route.f22() {
    get("/x22") { call.respondText("ok") }
    route("/k42") { f42() }
    route("/k6") { f6() }
    route("/k11") { f11() }
}
fun Route.f23() {
    get("/x23") { call.respondText("ok") }
    route("/k41") { f41() }
    route("/k47") { f47() }
    route("/k56") { f56() }
}
fun Route.f24() {
    get("/x24") { call.respondText("ok") }
    route("/k18") { f18() }
    route("/k7") { f7() }
    route("/k48") { f48() }
}
fun Route.f25() {
    get("/x25") { call.respondText("ok") }
    route("/k21") { f21() }
    route("/k58") { f58() }
    route("/k47") { f47() }
}
fun Route.f26() {
    get("/x26") { call.respondText("ok") }
    route("/k46") { f46() }
    route("/k33") { f33() }
    route("/k28") { f28() }
}
fun Route.f27() {
    get("/x27") { call.respondText("ok") }
    route("/k33") { f33() }
    route("/k54") { f54() }
    route("/k59") { f59() }
}
fun Route.f28() {
    get("/x28") { call.respondText("ok") }
    route("/k43") { f43() }
    route("/k12") { f12() }
    route("/k19") { f19() }
}
fun Route.f29() {
    get("/x29") { call.respondText("ok") }
    route("/k18") { f18() }
    route("/k38") { f38() }
    route("/k57") { f57() }
}
fun Route.f30() {
    get("/x30") { call.respondText("ok") }
    route("/k32") { f32() }
    route("/k55") { f55() }
    route("/k33") { f33() }
}
fun Route.f31() {
    get("/x31") { call.respondText("ok") }
    route("/k25") { f25() }
    route("/k38") { f38() }
    route("/k55") { f55() }
}
fun Route.f32() {
    get("/x32") { call.respondText("ok") }
    route("/k2") { f2() }
    route("/k30") { f30() }
    route("/k15") { f15() }
}
fun Route.f33() {
    get("/x33") { call.respondText("ok") }
    route("/k48") { f48() }
    route("/k52") { f52() }
    route("/k25") { f25() }
}
fun Route.f34() {
    get("/x34") { call.respondText("ok") }
    route("/k26") { f26() }
    route("/k43") { f43() }
    route("/k11") { f11() }
}
fun Route.f35() {
    get("/x35") { call.respondText("ok") }
    route("/k23") { f23() }
    route("/k36") { f36() }
    route("/k57") { f57() }
}
fun Route.f36() {
    get("/x36") { call.respondText("ok") }
    route("/k45") { f45() }
    route("/k50") { f50() }
    route("/k44") { f44() }
}
fun Route.f37() {
    get("/x37") { call.respondText("ok") }
    route("/k48") { f48() }
    route("/k23") { f23() }
    route("/k5") { f5() }
}
fun Route.f38() {
    get("/x38") { call.respondText("ok") }
    route("/k28") { f28() }
    route("/k43") { f43() }
    route("/k32") { f32() }
}
fun Route.f39() {
    get("/x39") { call.respondText("ok") }
    route("/k6") { f6() }
    route("/k50") { f50() }
    route("/k10") { f10() }
}
fun Route.f40() {
    get("/x40") { call.respondText("ok") }
    route("/k33") { f33() }
    route("/k54") { f54() }
    route("/k25") { f25() }
}
fun Route.f41() {
    get("/x41") { call.respondText("ok") }
    route("/k23") { f23() }
    route("/k31") { f31() }
    route("/k47") { f47() }
}
fun Route.f42() {
    get("/x42") { call.respondText("ok") }
    route("/k1") { f1() }
    route("/k30") { f30() }
    route("/k2") { f2() }
}
fun Route.f43() {
    get("/x43") { call.respondText("ok") }
    route("/k19") { f19() }
    route("/k46") { f46() }
    route("/k55") { f55() }
}
fun Route.f44() {
    get("/x44") { call.respondText("ok") }
    route("/k39") { f39() }
    route("/k37") { f37() }
    route("/k25") { f25() }
}
fun Route.f45() {
    get("/x45") { call.respondText("ok") }
    route("/k41") { f41() }
    route("/k10") { f10() }
    route("/k32") { f32() }
}
fun Route.f46() {
    get("/x46") { call.respondText("ok") }
    route("/k14") { f14() }
    route("/k0") { f0() }
    route("/k50") { f50() }
}
fun Route.f47() {
    get("/x47") { call.respondText("ok") }
    route("/k12") { f12() }
    route("/k34") { f34() }
    route("/k59") { f59() }
}
fun Route.f48() {
    get("/x48") { call.respondText("ok") }
    route("/k56") { f56() }
    route("/k35") { f35() }
    route("/k14") { f14() }
}
fun Route.f49() {
    get("/x49") { call.respondText("ok") }
    route("/k25") { f25() }
    route("/k32") { f32() }
    route("/k22") { f22() }
}
fun Route.f50() {
    get("/x50") { call.respondText("ok") }
    route("/k55") { f55() }
    route("/k36") { f36() }
    route("/k22") { f22() }
}
fun Route.f51() {
    get("/x51") { call.respondText("ok") }
    route("/k29") { f29() }
    route("/k59") { f59() }
    route("/k17") { f17() }
}
fun Route.f52() {
    get("/x52") { call.respondText("ok") }
    route("/k42") { f42() }
    route("/k35") { f35() }
    route("/k38") { f38() }
}
fun Route.f53() {
    get("/x53") { call.respondText("ok") }
    route("/k46") { f46() }
    route("/k0") { f0() }
    route("/k24") { f24() }
}
fun Route.f54() {
    get("/x54") { call.respondText("ok") }
    route("/k50") { f50() }
    route("/k55") { f55() }
    route("/k52") { f52() }
}
fun Route.f55() {
    get("/x55") { call.respondText("ok") }
    route("/k57") { f57() }
    route("/k47") { f47() }
    route("/k32") { f32() }
}
fun Route.f56() {
    get("/x56") { call.respondText("ok") }
    route("/k51") { f51() }
    route("/k8") { f8() }
    route("/k33") { f33() }
}
fun Route.f57() {
    get("/x57") { call.respondText("ok") }
    route("/k49") { f49() }
    route("/k35") { f35() }
    route("/k13") { f13() }
}
fun Route.f58() {
    get("/x58") { call.respondText("ok") }
    route("/k27") { f27() }
    route("/k3") { f3() }
    route("/k30") { f30() }
}
fun Route.f59() {
    get("/x59") { call.respondText("ok") }
    route("/k55") { f55() }
    route("/k23") { f23() }
    route("/k36") { f36() }
}