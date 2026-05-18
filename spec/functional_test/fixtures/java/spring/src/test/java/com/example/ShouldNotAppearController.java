// Regression guard: Maven/Gradle convention puts unit and
// integration tests under `src/test/java/...`. Spring projects
// routinely declare inline `@RestController` classes there to
// exercise MockMvc / WebTestClient, but the routes never serve
// real traffic. None of the URLs below should appear in the
// fixture's expected-endpoints list.
package com.example;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ShouldNotAppearController {
    @GetMapping("/should-not-appear-test-get")
    public String get() {
        return "";
    }

    @PostMapping("/should-not-appear-test-post")
    public String post() {
        return "";
    }
}
