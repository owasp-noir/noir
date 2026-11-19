package com.acme;

import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.ServerRequest;
import org.springframework.web.reactive.function.server.ServerResponse;
import reactor.core.publisher.Mono;

@Component
public class PersonHandler {
    public Mono<ServerResponse> listPeople(ServerRequest request) {
        String name = request.queryParam("name").orElse("");
        String tenant = request.headers().firstHeader("X-Tenant");
        return ServerResponse.ok().build();
    }

    public Mono<ServerResponse> createPerson(ServerRequest request) {
        Mono<Person> person = request.bodyToMono(Person.class);
        return ServerResponse.ok().build(person.then());
    }

    public Mono<ServerResponse> getPerson(ServerRequest request) {
        int personId = Integer.valueOf(request.pathVariable("id"));
        return ServerResponse.ok().build();
    }
}
