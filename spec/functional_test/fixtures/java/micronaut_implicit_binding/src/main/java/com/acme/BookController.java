package com.acme;

import io.micronaut.core.annotation.Nullable;
import io.micronaut.http.annotation.*;
import java.util.Optional;

@Controller("/books")
public class BookController {
    // Micronaut guide "Routing > Variables Resolution": an argument with no
    // annotation is filled from the URI variables, then (GET) the query string.
    @Get("/search")
    public String search(String title, @Nullable String author, Optional<Integer> max) { return "x"; }

    // Control: the same inputs spelled with @QueryValue.
    @Get("/search-explicit")
    public String searchExplicit(@QueryValue String title, @QueryValue @Nullable String author, @QueryValue Optional<Integer> max) { return "x"; }

    // Path variable plus an implicit query value.
    @Get("/{id}/pages")
    public String pages(Long id, @Nullable Integer from) { return "x"; }

    // ...and for a request with a body and no @Body, each argument is a
    // property of the JSON (or form) body.
    @Post("/login")
    public String login(String username, String password) { return "x"; }
}
