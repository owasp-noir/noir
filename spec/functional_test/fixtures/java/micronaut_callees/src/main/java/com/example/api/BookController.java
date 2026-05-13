package com.example.api;

import io.micronaut.http.HttpResponse;
import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;
import io.micronaut.http.annotation.PathVariable;
import io.micronaut.http.annotation.Post;
import io.micronaut.http.annotation.QueryValue;

@Controller("/books")
public class BookController {
    private final BookService service = new BookService();

    @Post("/{id}")
    public HttpResponse<?> create(@PathVariable long id,
                                  @QueryValue("dry_run") boolean dryRun) {
        validate(id);
        service.save(id, dryRun);
        AuditLog.write("create");
        return HttpResponse.ok();
    }

    @Get(uris = {"/popular", "/featured"})
    public HttpResponse<?> highlights() {
        String profile = this.buildProfile();
        AuditLog.write(profile);
        return HttpResponse.ok(profile);
    }

    private void validate(long id) {}

    private String buildProfile() {
        return "profile";
    }
}

class BookService {
    void save(long id, boolean dryRun) {}
}

class AuditLog {
    static void write(String event) {}
}
