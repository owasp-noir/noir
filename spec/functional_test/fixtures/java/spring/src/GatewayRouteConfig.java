package org.test;

import org.springframework.cloud.gateway.handler.predicate.PredicateSpec;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;

@Configuration
public class GatewayRouteConfig {

    private static final String MCP_ENDPOINT_PATH = "/gateway/mcp";

    @Bean
    public RouteLocator customRouteLocator(RouteLocatorBuilder builder) {
        return builder.routes()
            .route("post_mcp", r -> r.method(HttpMethod.POST).and().path(MCP_ENDPOINT_PATH).uri("no://op"))
            .route("get_report", r -> isGetReportRoute(r).uri("no://op"))
            .build();
    }

    private PredicateSpec isGetReportRoute(PredicateSpec predicateSpec) {
        return predicateSpec.method(HttpMethod.GET).and().path("/gateway/reports/{id}");
    }
}
