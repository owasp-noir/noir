// Regression guard: WebMvc.fn / WebFlux.fn `nest()` prefix.
// `nest(RequestPredicates.path("/product"), builder -> ...)` /
// `nest(path("/product"), ...)` adds `/product` to every verb
// call inside the lambda. Without prefix awareness routes would
// surface stripped of the prefix.
package org.test;

import static org.springframework.web.servlet.function.RouterFunctions.route;
import static org.springframework.web.servlet.function.ServerResponse.ok;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.function.RequestPredicates;
import org.springframework.web.servlet.function.RouterFunction;
import org.springframework.web.servlet.function.ServerResponse;

@Configuration
public class ProductRouter {

    @Bean
    public RouterFunction<ServerResponse> productSearch() {
        return route().nest(RequestPredicates.path("/product"), builder -> builder
                .GET("/name/{name}", req -> ok().body("by-name"))
                .GET("/id/{id}", req -> ok().body("by-id")))
            .build();
    }
}
