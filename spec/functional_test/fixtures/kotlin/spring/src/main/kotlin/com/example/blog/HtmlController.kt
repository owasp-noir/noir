package com.example.blog

import org.springframework.http.HttpStatus.*
import org.springframework.http.ResponseEntity
import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.ui.set
import org.springframework.web.bind.annotation.*
import java.time.LocalDateTime
import org.springframework.web.server.ResponseStatusException

@Controller
class HtmlController(private val repository: ArticleRepository,
                     private val properties: BlogProperties) {

    @GetMapping("/v1", params = ["version=1"])
    fun blogV1(model: Model): String {
        model["title"] = "${properties.title} - v1"
        model["banner"] = properties.banner
        model["articles"] = repository.findAllByOrderByAddedAtDesc().map { it.render() }
        return "blog"
    }

    @GetMapping(path = ["/v2", "/version2"], params = ["version=2"])
    fun blogV2(model: Model): String {
        model["title"] = "${properties.title} - v2"
        model["banner"] = properties.banner
        model["articles"] = repository.findAllByOrderByAddedAtDesc().map { it.renderV2() }
        return "blog"
    }

    @GetMapping(value = ["/v3", "/version3"], params = ["version=3"])
    fun blogV3(model: Model): String {
        model["title"] = "${properties.title} - v3"
        model["banner"] = properties.banner
        model["articles"] = repository.findAllByOrderByAddedAtDesc().map { it.renderV2() }
        return "blog"
    }

    @PostMapping("/article", consumes = ["application/json"], produces = ["application/json"])
    fun createArticleJson(@RequestBody article: Article): ResponseEntity<RenderedArticle> {
        val savedArticle = repository.save(article)
        return ResponseEntity(savedArticle.render(), CREATED)
    }

    @PostMapping("/article2", consumes = ["application/x-www-form-urlencoded"])
    fun createArticleForm(@RequestParam title: String, @RequestParam content: String, model: Model): String {
        val article = Article(title = title, content = content, author = User("authorLogin", "Author", "Lastname"))
        repository.save(article)
        model["message"] = "Article created"
        return "response"
    }

    @GetMapping("/article/{slug}")
    fun article(@PathVariable slug: String, @RequestParam(defaultValue = "false") preview: Boolean, model: Model): String {
        val article = repository
            .findBySlug(slug)
            ?.render()
            ?: throw ResponseStatusException(NOT_FOUND, "This article does not exist")
        model["title"] = article.title
        model["article"] = article
        model["preview"] = preview
        return "article"
    }

    @PutMapping("/article/{id}", consumes = ["application/json"])
    fun updateArticleJson(@PathVariable id: Long, @RequestBody updateData: UpdateData, model: Model): String {
        val article = repository.findById(id).orElseThrow { ResponseStatusException(NOT_FOUND, "This article does not exist") }
        article.title = updateData.title
        article.content = updateData.content
        repository.save(article)
        model["message"] = "Article updated"
        return "response"
    }

    @DeleteMapping("/article/{id}", params = ["soft"], headers = ["X-Custom-Header=soft-delete"])
    fun softDeleteArticle(@PathVariable id: Long, model: Model): String {
        val article = repository.findById(id).orElseThrow { ResponseStatusException(NOT_FOUND, "This article does not exist") }
        article.deleted = true
        repository.save(article)
        model["message"] = "Article soft deleted"
        return "response"
    }

    @DeleteMapping("/article2/{id}")
    fun deleteArticle(@PathVariable id: Long, model: Model): String {
        repository.deleteById(id)
        model["message"] = "Article deleted"
        return "response"
    }

    @PatchMapping("/article/{id}", consumes = arrayOf("application/json"))
    fun patchArticleJson(@PathVariable id: Long, @RequestBody patchData: PatchData, model: Model): String {
        val article = repository.findById(id).orElseThrow { ResponseStatusException(NOT_FOUND, "This article does not exist") }
        article.title = patchData.title ?: article.title
        article.content = patchData.content ?: article.content
        repository.save(article)
        model["message"] = "Article patched"
        return "response"
    }

    @RequestMapping("/request", method = [RequestMethod.GET, RequestMethod.POST], params = ["type=basic"], headers = ["X-Custom-Header=basic"])
    fun handleRequestBasic(model: Model): String {
        model["message"] = "Handled by @RequestMapping with type=basic and custom header"
        return "response"
    }

    @RequestMapping("/request2", method = [RequestMethod.GET, RequestMethod.POST], params = ["type=advanced"], headers = ["X-Custom-Header=advanced"])
    fun handleRequestAdvanced(model: Model): String {
        model["message"] = "Handled by @RequestMapping with type=advanced and custom header"
        return "response"
    }

    fun Article.render() = RenderedArticle(
        slug,
        title,
        headline,
        content,
        author,
        addedAt.format()
    )

    fun Article.renderV2() = RenderedArticleV2(
        slug,
        title,
        headline,
        content,
        author,
        addedAt.format()
    )

    data class RenderedArticle(
        val slug: String,
        val title: String,
        val headline: String,
        val content: String,
        val author: User,
        val addedAt: String
    )

    data class RenderedArticleV2(
        val slug: String,
        val title: String,
        val headline: String,
        val content: String,
        val author: User,
        val addedAt: String
    )

    data class UpdateData(
        val title: String,
        val content: String
    )

    data class PatchData(
        val title: String?,
        val content: String?
    )
}
