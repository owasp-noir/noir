package com.example.api;

import io.micronaut.http.HttpResponse;
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

@Controller("/books")
public class BookController {

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

    @Post
    @Consumes(MediaType.APPLICATION_JSON)
    public HttpResponse<?> create(@Body Book book) {
        return HttpResponse.created("");
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

    @Patch("/{id}")
    @Consumes(MediaType.APPLICATION_JSON)
    public HttpResponse<?> patch(@PathVariable long id, Book book) {
        return HttpResponse.ok();
    }
}
