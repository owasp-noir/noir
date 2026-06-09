package com.example

import org.springframework.graphql.data.method.annotation.Argument
import org.springframework.graphql.data.method.annotation.MutationMapping
import org.springframework.graphql.data.method.annotation.QueryMapping
import org.springframework.graphql.data.method.annotation.SchemaMapping
import org.springframework.stereotype.Controller

@Controller
class GraphqlController(private val articleService: ArticleService) {
    @QueryMapping
    fun article(@Argument id: String): Article {
        return articleService.findArticle(id)
    }

    @MutationMapping("createArticle")
    fun create(@Argument("input") request: CreateArticleInput): Article {
        return articleService.createArticle(request)
    }

    @MutationMapping
    fun addComment(@Argument(name = ARTICLE_ID_ARG) id: String, @Argument input: CommentInput): Comment {
        return articleService.addComment(id, input)
    }

    @MutationMapping
    fun createTaggedArticle(@Argument tags: List<TagInput>): Article {
        return articleService.createTaggedArticle(tags)
    }

    @SchemaMapping
    fun author(article: Article): User {
        return articleService.findAuthor(article.authorId)
    }

    @SchemaMapping(field = "comments")
    fun articleComments(article: Article): List<Comment> {
        return articleService.findComments(article.id)
    }

    @QueryMapping
    fun ping(): String = "ok"
}

class ArticleService {
    fun findArticle(id: String): Article = Article(id)
    fun createArticle(input: CreateArticleInput): Article = Article(input.title)
    fun addComment(id: String, input: CommentInput): Comment = Comment(id, input.body)
    fun createTaggedArticle(tags: List<TagInput>): Article = Article(tags.first().label)
    fun findAuthor(authorId: String): User = User(authorId)
    fun findComments(articleId: String): List<Comment> = listOf(Comment(articleId, "ok"))
}

data class Article(val id: String, val authorId: String = id)
data class CreateArticleInput(val title: String)
data class Comment(val articleId: String, val body: String)
data class CommentInput(val body: String)
data class TagInput(val label: String)
data class User(val id: String)

const val ARTICLE_ID_ARG = "articleId"
