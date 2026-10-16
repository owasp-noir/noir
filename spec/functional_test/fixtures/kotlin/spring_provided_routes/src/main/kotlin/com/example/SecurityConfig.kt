package com.example

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.annotation.web.invoke
import org.springframework.security.web.SecurityFilterChain

@Configuration
class SecurityConfig {
    @Bean
    fun chain(http: HttpSecurity): SecurityFilterChain {
        http {
            formLogin { loginPage = "/auth/login" }
            logout { logoutUrl = "/bye" }
            oauth2Login { authorizationEndpoint { baseUri = "/oauth/start" } }
            httpBasic { disable() }
        }
        return http.build()
    }
}
