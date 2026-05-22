package com.example.api;

import io.micronaut.http.HttpResponse;
import io.micronaut.http.MediaType;
import io.micronaut.http.annotation.Body;
import io.micronaut.http.annotation.Get;
import io.micronaut.http.annotation.PathVariable;
import io.micronaut.http.annotation.Post;
import io.micronaut.http.annotation.QueryValue;

public interface BookApi {
    @Get("/interface/{isbn}")
    HttpResponse<?> interfaceLookup(@PathVariable String isbn,
                                    @QueryValue("edition") String edition);

    @Post(value = "/interface", consumes = MediaType.APPLICATION_JSON)
    HttpResponse<?> interfaceCreate(@Body Book book);
}
