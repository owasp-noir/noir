package demo.router;

import static org.springframework.web.reactive.function.server.RequestPredicates.accept;
import static org.springframework.web.reactive.function.server.RequestPredicates.path;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.RouterFunctions;
import org.springframework.web.reactive.function.server.ServerRequest;
import org.springframework.web.reactive.function.server.ServerResponse;
import reactor.core.publisher.Mono;

@Configuration
public class ProfileRouter {
    @Bean
    RouterFunction<ServerResponse> completeProfile() {
        return RouterFunctions.nest(
                path("/complete-profile"),
                RouterFunctions.route()
                        .GET("", this::page)
                        .POST("/send-email-code", this::send)
                        .build());
    }

    @Bean
    RouterFunction<ServerResponse> setupPage() {
        return RouterFunctions.route()
                .GET(path("/system/setup").and(accept(MediaType.TEXT_HTML)), this::page)
                .GET(path("/system/status"), this::page)
                .POST("/system/setup", this::send)
                .build();
    }

    @Bean
    RouterFunction<ServerResponse> builderVariable() {
        RouterFunctions.Builder b = RouterFunctions.route();
        b.GET("/builder/a", this::page);
        b.POST("/builder/b", this::send);
        return b.build();
    }

    Mono<ServerResponse> page(ServerRequest request) { return ServerResponse.ok().build(); }

    Mono<ServerResponse> send(ServerRequest request) { return ServerResponse.ok().build(); }
}
