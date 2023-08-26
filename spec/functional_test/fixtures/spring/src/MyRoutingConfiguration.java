package org.springframework.boot.docs.web.reactive.webflux;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.server.RequestPredicate;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.ServerResponse;

import static org.springframework.web.reactive.function.server.RequestPredicates.accept;
import static org.springframework.web.reactive.function.server.RouterFunctions.route;

@Configuration(proxyBeanMethods = false)
public class MyRoutingConfiguration {

	private static final RequestPredicate ACCEPT_JSON = accept(MediaType.APPLICATION_JSON);

	@Bean
	public RouterFunction<ServerResponse> monoRouterFunction(MyUserHandler userHandler) {
		// @formatter:off
		return route()
				/* Get */
				.GET("/{user}", ACCEPT_JSON, userHandler::getUser)
				.GET("/{user}/customers", ACCEPT_JSON, userHandler::getUserCustomers)
				.GET("/{user}/0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_.~", ACCEPT_JSON, userHandler::getUserCustomers)
				// Delete
				.DELETE("/{user}", ACCEPT_JSON, userHandler::deleteUser)
				.build();
		// @formatter:on
	}

	@Bean
	public RouterFunction<ServerResponse> monoRouterFunction2(MyUserHandler userHandler) {
		// @formatter:off
		return route().POST("/{user}", ACCEPT_JSON, userHandler::getUser)
				.PUT("/{user}", ACCEPT_JSON, userHandler::getUserCustomers)
				.build();
		// @formatter:on
	}

}