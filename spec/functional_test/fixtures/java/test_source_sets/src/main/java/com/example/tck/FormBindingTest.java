package com.example.tck;

import io.micronaut.context.annotation.Requires;
import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Post;

// JUnit class shipped in src/main/java of a published test kit (Micronaut TCK
// shape): the controller only exists while a test scenario runs.
public class FormBindingTest {
    @Requires(property = "spec.name", value = "FormBindingTest")
    @Controller("/tck-book")
    static class SaveController {
        @Post("/save")
        String save(String title) {
            return title;
        }
    }
}
