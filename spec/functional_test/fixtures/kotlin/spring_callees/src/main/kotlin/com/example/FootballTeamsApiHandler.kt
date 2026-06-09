package com.example

import org.springframework.web.client.RestTemplate

class FootballTeamsApiHandler {
    fun getAllPages(nation: String): String {
        return getResponse(nation)
    }

    private fun getResponse(nation: String): String {
        val restTemplate = RestTemplate()
        return restTemplate.getForObject("https://example.com/$nation", String::class.java) ?: ""
    }
}
