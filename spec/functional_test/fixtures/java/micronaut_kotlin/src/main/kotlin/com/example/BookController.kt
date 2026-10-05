package com.example

import com.example.model.Book
import io.micronaut.http.HttpRequest
import io.micronaut.http.HttpResponse
import io.micronaut.http.MediaType
import io.micronaut.http.annotation.Body
import io.micronaut.http.annotation.Controller
import io.micronaut.http.annotation.CookieValue
import io.micronaut.http.annotation.CustomHttpMethod
import io.micronaut.http.annotation.Delete
import io.micronaut.http.annotation.Get
import io.micronaut.http.annotation.Header
import io.micronaut.http.annotation.Post
import io.micronaut.http.annotation.Put
import io.micronaut.http.annotation.QueryValue
import io.micronaut.validation.Validated
import reactor.core.publisher.Mono

@Validated
@Controller("/books")
class BookController(private val repository: BookRepository) {
    @Get
    fun list(@QueryValue(defaultValue = "10") max: Int, @Header("X-Trace") trace: String?): List<Book> =
        repository.findAll(max)

    @Get("/{id}")
    fun show(id: Long, request: HttpRequest<*>): Book? = repository.find(id)

    @Get(uri = "/search{?q,limit}")
    fun search(q: String, limit: Int?): List<Book> = repository.search(q, limit)

    @Post
    fun save(@Body book: Book): HttpResponse<Book> = HttpResponse.created(repository.save(book))

    @Post(value = "/form", consumes = [MediaType.APPLICATION_FORM_URLENCODED])
    fun form(book: Book): Book = repository.save(book)

    @Put("/{id}")
    fun update(id: Long, @Body book: Mono<Book>): Mono<Book> = book.map { repository.update(id, it) }

    @Delete("/{id}")
    fun delete(id: Long, @CookieValue("session") session: String) {
        repository.delete(id)
    }

    @CustomHttpMethod(method = "QUERY", value = "/advanced")
    fun advanced(@Body criteria: Book): List<Book> = repository.query(criteria)
}
