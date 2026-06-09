package com.example

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.asFlow
import org.springframework.graphql.data.method.annotation.Argument
import org.springframework.graphql.data.method.annotation.MutationMapping
import org.springframework.graphql.data.method.annotation.QueryMapping
import org.springframework.stereotype.Controller

@Controller
class GraphqlArticleController(private val articleService: ArticleService) {
    @QueryMapping
    fun articles(): Flow<Article> {
        return articleService.findAllArticles()
    }

    @MutationMapping
    fun createArticle(@Argument input: CreateArticleInput): Article {
        return articleService.createArticle(input)
    }
}

class ArticleService {
    private val articles = mutableListOf<Article>()

    fun findAllArticles(): Flow<Article> {
        return articles.asFlow()
    }

    fun createArticle(input: CreateArticleInput): Article {
        return Article(
            id = input.userId,
            title = input.title,
        ).also { articles.add(it) }
    }
}

data class CreateArticleInput(
    val title: String,
    val userId: String,
)

data class Article(
    val id: String,
    val title: String,
)
