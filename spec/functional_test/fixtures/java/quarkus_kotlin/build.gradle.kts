plugins {
    kotlin("jvm") version "2.0.21"
    id("io.quarkus")
}

dependencies {
    implementation("io.quarkus:quarkus-rest-jackson")
    implementation("io.quarkus:quarkus-reactive-routes")
}
