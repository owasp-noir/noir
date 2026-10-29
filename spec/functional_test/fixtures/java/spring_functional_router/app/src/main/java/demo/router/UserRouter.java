package demo.router;

import static org.springframework.web.reactive.function.server.RouterFunctions.route;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.ServerRequest;
import org.springframework.web.reactive.function.server.ServerResponse;
import reactor.core.publisher.Mono;

@Configuration
public class UserRouter {
    @Bean
    public RouterFunction<ServerResponse> users() {
        return route()
            .GET("/users/{name}", this::get)
            .GET("/users/search", request -> {
                var keyword = request.queryParam("q");
                return ServerResponse.ok().build();
            })
            .GET("/users", this::list)
            .POST("/users", this::create, ops -> { ops.operationId("CreateUser"); })
            .DELETE("/users/{name}", this::delete)
            .build();
    }

    Mono<ServerResponse> get(ServerRequest r) { return ServerResponse.ok().build(); }

    Mono<ServerResponse> list(ServerRequest r) {
        var keyword = r.queryParam("keyword");
        return ServerResponse.ok().build();
    }

    Mono<ServerResponse> create(ServerRequest r) {
        r.bodyToMono(CreateUser.class);
        r.headers().firstHeader("X-Token");
        return ServerResponse.ok().build();
    }

    Mono<ServerResponse> delete(ServerRequest r) { return ServerResponse.ok().build(); }
}
