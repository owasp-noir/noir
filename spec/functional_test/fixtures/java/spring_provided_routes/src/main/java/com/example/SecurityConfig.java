package com.example;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
public class SecurityConfig {
    @Bean
    SecurityFilterChain chain(HttpSecurity http) throws Exception {
        return http.formLogin(f -> f.loginProcessingUrl("/signin/do").usernameParameter("handle").passwordParameter("secret"))
                   .logout(l -> l.logoutUrl("/signout"))
                   .oauth2Login(o -> o.redirectionEndpoint(r -> r.baseUri("/sso/callback/*")))
                   .build();
    }

    // An application method named like a configurer is not a route.
    public void logout() {
    }
}
