import org.springframework.boot.gradle.tasks.bundling.BootJar

dependencies {
    api("org.springframework.boot:spring-boot-starter-actuator")
}

tasks.getByName<BootJar>("bootJar") {
    enabled = false
}
