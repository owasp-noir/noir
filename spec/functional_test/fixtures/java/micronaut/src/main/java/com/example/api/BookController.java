package com.example.api;

import io.micronaut.http.HttpResponse;
import io.micronaut.http.HttpRequest;
import io.micronaut.http.MediaType;
import io.micronaut.http.annotation.Body;
import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Consumes;
import io.micronaut.http.annotation.CookieValue;
import io.micronaut.http.annotation.Delete;
import io.micronaut.http.annotation.Get;
import io.micronaut.http.annotation.Header;
import io.micronaut.http.annotation.Patch;
import io.micronaut.http.annotation.PathVariable;
import io.micronaut.http.annotation.Post;
import io.micronaut.http.annotation.Put;
import io.micronaut.http.annotation.QueryValue;
import io.micronaut.http.annotation.RequestBean;
import io.micronaut.http.multipart.CompletedFileUpload;
import io.micronaut.security.authentication.Authentication;
import java.security.Principal;
import java.time.Month;

@Controller("/books")
public class BookController implements BookApi {
    private static final String ADMIN_PREFIX = "/admin";
    private static final String STATS_PATH = "/stats";
    private static final String CODE_PARAM = "code";
    private static final String CODE_DEFAULT = "none";
    private static final String CODE_HEADER = "X-Code";
    private static final String SESSION_COOKIE = "session-id";

    static final class Routes {
        static final String EXPORT = "/export";
    }

    @Get
    public HttpResponse<?> list(@QueryValue("page") int page,
                                @QueryValue int size) {
        return HttpResponse.ok();
    }

    @Get("/{id}")
    public HttpResponse<?> get(@PathVariable long id,
                               @Header("X-Trace") String trace) {
        return HttpResponse.ok();
    }

    @Get(uris = {"/popular", "/featured"})
    public HttpResponse<?> highlights() {
        return HttpResponse.ok();
    }

    @Get(ADMIN_PREFIX + STATS_PATH)
    public HttpResponse<?> adminStats() {
        return HttpResponse.ok();
    }

    @Get(uri = Routes.EXPORT)
    public HttpResponse<?> export() {
        return HttpResponse.ok();
    }

    @Get(value = "/search", produces = MediaType.APPLICATION_JSON)
    public HttpResponse<?> search(@QueryValue(value = "q", defaultValue = "all") String query,
                                  @Header(name = "X-Client") String client) {
        return HttpResponse.ok();
    }

    @Get("/constants")
    public HttpResponse<?> constants(@QueryValue(value = CODE_PARAM, defaultValue = CODE_DEFAULT) String code,
                                     @Header(CODE_HEADER) String header) {
        return HttpResponse.ok();
    }

    @Get("/filter")
    public HttpResponse<?> filter(@RequestBean BookFilter filter) {
        return HttpResponse.ok();
    }

    @Get("/template{?q}")
    public HttpResponse<?> template(@QueryValue String q) {
        return HttpResponse.ok();
    }

    @Get("/paged{?filter*}")
    public HttpResponse<?> paged(BookFilter filter) {
        return HttpResponse.ok();
    }

    @Get("/calendar/{month}")
    public HttpResponse<?> calendar(Month month, Principal principal, Authentication authentication, HttpRequest<?> request) {
        return HttpResponse.ok();
    }

    @Post
    @Consumes(MediaType.APPLICATION_JSON)
    public HttpResponse<?> create(@Body Book book) {
        return HttpResponse.created("");
    }

    @Post(value = "/forms", consumes = MediaType.APPLICATION_FORM_URLENCODED)
    public HttpResponse<?> formBody(@Body Book book) {
        return HttpResponse.ok();
    }

    @Post("/attachment")
    @Consumes(MediaType.MULTIPART_FORM_DATA)
    public HttpResponse<?> attachment(CompletedFileUpload file) {
        return HttpResponse.ok();
    }

    @Post("/scalar")
    public HttpResponse<?> scalarBody(@Body("isbn") String isbn,
                                      @Body("name") String name) {
        return HttpResponse.ok();
    }

    @Post("/login")
    @Consumes(MediaType.APPLICATION_FORM_URLENCODED)
    public HttpResponse<?> login(@QueryValue String username,
                                 @QueryValue("pwd") String password) {
        return HttpResponse.ok();
    }

    @Put("/{id}")
    @Consumes(MediaType.APPLICATION_JSON)
    public HttpResponse<?> update(@PathVariable long id, @Body Book book) {
        return HttpResponse.ok();
    }

    @Delete("/{id}")
    public HttpResponse<?> delete(@PathVariable long id,
                                  @CookieValue("session") String session) {
        return HttpResponse.noContent();
    }

    @Delete("/constants")
    public HttpResponse<?> deleteConstants(@CookieValue(SESSION_COOKIE) String sessionId) {
        return HttpResponse.noContent();
    }

    @Patch("/{id}")
    @Consumes(MediaType.APPLICATION_JSON)
    public HttpResponse<?> patch(@PathVariable long id, Book book) {
        return HttpResponse.ok();
    }

    @Override
    public HttpResponse<?> interfaceLookup(String isbn, String edition) {
        return HttpResponse.ok();
    }

    @Override
    public HttpResponse<?> interfaceCreate(Book book) {
        return HttpResponse.created("");
    }
}

class BookFilter {
    private String author;
    private Integer year;

    public void setAuthor(String author) { this.author = author; }
    public void setYear(Integer year) { this.year = year; }
}
