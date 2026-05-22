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
import org.springframework.http.MediaType;
import org.springframework.web.servlet.function.RequestPredicates;
import org.springframework.web.servlet.function.RouterFunction;
import org.springframework.web.servlet.function.ServerResponse;

@Configuration
public class ProductRouter {
    private static final String PRODUCT_ROOT = "/product";
    private static final String NAME_SEGMENT = "/name";
    private static final String API_ROOT = "/api";
    private static final String API_VERSION = "/v1";
    private static final String CATALOG_ROOT = "/catalog";

    @Bean
    public RouterFunction<ServerResponse> productSearch() {
        return route().nest(RequestPredicates.path(PRODUCT_ROOT), builder -> builder
                .GET(NAME_SEGMENT + "/{name}", req -> ok().body("by-name"))
                .GET("/id/{id}", req -> ok().body("by-id")))
            .build();
    }

    @Bean
    public RouterFunction<ServerResponse> catalogRoutes() {
        return route().nest(RequestPredicates.path(API_ROOT).and(RequestPredicates.accept(MediaType.APPLICATION_JSON)),
            api -> api.nest(RequestPredicates.path(API_VERSION), v1 -> v1
                    .GET(CATALOG_ROOT + "/{id}", req -> ok().body("by-id"))
                    .POST(CATALOG_ROOT, req -> ok().body("created"))))
            .build();
    }
}
