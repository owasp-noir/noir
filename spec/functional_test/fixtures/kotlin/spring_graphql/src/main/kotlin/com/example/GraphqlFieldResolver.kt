package com.example

import org.springframework.graphql.data.method.annotation.SchemaMapping
import org.springframework.stereotype.Controller

@Controller
class GraphqlFieldResolver(private val summaryService: SummaryService) {
    @SchemaMapping(typeName = "Article", field = "summary")
    fun summary(article: Article): String {
        return summaryService.buildSummary(article.id)
    }
}

class SummaryService {
    fun buildSummary(articleId: String): String = articleId
}
