package com.acme;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.ServerRequest;
import org.springframework.web.reactive.function.server.ServerResponse;
import reactor.core.publisher.Mono;

import static org.springframework.web.reactive.function.server.RouterFunctions.route;

@Configuration
public class RoutingConfiguration {
    @Bean
    public RouterFunction<ServerResponse> personRoutes(PersonHandler handler) {
        return route()
            .GET("/person/{id}", handler::getPerson)
            .GET("/person", handler::listPeople)
            .POST("/person", handler::createPerson)
            // Control: same reads, handler method in this file.
            .GET("/local", this::local)
            .build();
    }

    private Mono<ServerResponse> local(ServerRequest request) {
        String name = request.queryParam("name").orElse("");
        String tenant = request.headers().firstHeader("X-Tenant");
        return ServerResponse.ok().build();
    }
}
