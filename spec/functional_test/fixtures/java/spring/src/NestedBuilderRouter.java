package com.test;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.server.*;
import static org.springframework.web.reactive.function.server.RequestPredicates.*;
import static org.springframework.web.reactive.function.server.RouterFunctions.*;

@Configuration
public class NestedBuilderRouter {
    @Bean
    public RouterFunction<ServerResponse> classic(PetHandler h) {
        return RouterFunctions.route(GET("/clinic"), h::clinic)
            .andNest(path("/clinic-admin"), route(GET("/stats"), h::stats).andRoute(DELETE("/cache"), h::clear));
    }

    @Bean
    public RouterFunction<ServerResponse> builder(PetHandler h) {
        return route()
            .path("/person", builder -> builder
                .nest(accept(MediaType.APPLICATION_JSON), b2 -> b2
                    .GET("/{id}", h::getPerson)
                    .GET(h::listPeople))
                .POST(h::createPerson))
            .path("/vets", b3 -> b3.GET("", h::vets))
            .build();
    }
}
