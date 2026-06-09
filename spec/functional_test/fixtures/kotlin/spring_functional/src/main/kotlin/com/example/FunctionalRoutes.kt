package com.example

import com.example.handlers.ImportedPostHandler
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.stereotype.Component
import org.springframework.web.reactive.function.server.ServerRequest
import org.springframework.web.reactive.function.server.ServerResponse
import org.springframework.web.reactive.function.server.coRouter
import org.springframework.web.reactive.function.server.bodyValueAndAwait
import org.springframework.web.reactive.function.server.buildAndAwait
import org.springframework.web.reactive.function.server.ServerResponse.ok
import org.springframework.web.reactive.function.server.ServerResponse.noContent

@Configuration
class RouterConfiguration {
    @Bean
    fun routes(postHandler: PostHandler, importedPostHandler: ImportedPostHandler, auditService: AuditService) = coRouter {
        "/posts".nest {
            GET("", postHandler::all)
            GET("/{id}", postHandler::get)
            POST("", postHandler::create)
            PUT("/{id}", postHandler::update)
            DELETE("/{id}", postHandler::delete)
        }
        GET("/imported", importedPostHandler::show)
        GET("/inline-audit") { auditService.record(); ok().buildAndAwait() }
        GET("/inline-empty") { ServerResponse.ok().build() }
    }
}

@Configuration
class ConstructorRouterConfiguration(private val importedPostHandler: ImportedPostHandler) {
    @Bean
    fun constructorRoutes() = coRouter {
        GET("/constructor-imported", importedPostHandler::show)
    }
}

@Component
class PostHandler(private val posts: PostRepository) {
    suspend fun all(req: ServerRequest): ServerResponse {
        return ok().bodyValueAndAwait(posts.findAll())
    }

    suspend fun get(req: ServerRequest): ServerResponse {
        return ok().bodyValueAndAwait(posts.findOne(req.pathVariable("id")))
    }

    suspend fun create(req: ServerRequest): ServerResponse {
        val body = req.awaitBody<PostInput>()
        val created = posts.save(body)
        PostView(created); ApiResponse.buildResponse(created); val view = PostView(created); view.copy(id = created); val model = DummyModel(); model.addAttribute("id", created); val resource = DummyResource(); resource.add(created); val results = listOf(created); results.map { it }; val num = java.util.concurrent.atomic.AtomicInteger(); num.incrementAndGet()
        val decorated = decorate(created)
        return ok().bodyValueAndAwait(decorated)
    }

    private fun decorate(id: String): String {
        return posts.findOne(id)
    }

    suspend fun update(req: ServerRequest): ServerResponse {
        posts.update(req.pathVariable("id"), req)
        return noContent().buildAndAwait()
    }

    suspend fun delete(req: ServerRequest): ServerResponse {
        posts.delete(req.pathVariable("id"))
        return noContent().buildAndAwait()
    }
}

class PostRepository {
    fun findAll(): List<String> = emptyList()
    fun findOne(id: String): String = id
    fun save(post: PostInput): String = "created"
    fun update(id: String, req: ServerRequest) {}
    fun delete(id: String) {}
}

data class PostInput(
    val title: String,
    val content: String
)

data class PostView(
    val id: String
)

object ApiResponse {
    fun buildResponse(value: String): String = value
}

class DummyModel {
    fun addAttribute(name: String, value: String) {}
}

class DummyResource {
    fun add(value: String) {}
}

class AuditService {
    fun record() {}
}
