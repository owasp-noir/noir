plugins {
    id("org.springframework.boot") version "3.3.0"
    kotlin("jvm") version "1.9.24"
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    // implementation("org.springdoc:springdoc-openapi-starter-webmvc-ui:2.6.0")
}
