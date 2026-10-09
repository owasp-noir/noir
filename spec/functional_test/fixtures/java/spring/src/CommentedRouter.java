package org.test;

import org.springframework.context.annotation.Bean;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.RouterFunctions;
import org.springframework.web.reactive.function.server.ServerResponse;

import static org.springframework.web.reactive.function.server.RequestPredicates.GET;

// Commented-out functional routes inside a live route block are not routes.
public class CommentedRouter {
	@Bean
	public RouterFunction<ServerResponse> route(QuoteHandler handler) {
		return RouterFunctions
				// .andRoute(GET("/commented-router"), handler::old)
				/* .andRoute(GET("/block-commented-router"), handler::old) */
				.route(GET("/live-router"), handler::hello);
	}
}
