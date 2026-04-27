package com.example.blog

class GatewayRouteConfig {
    fun customRouteLocator(builder: RouteLocatorBuilder): RouteLocator {
        val routesBuilder = builder.routes()
        routesBuilder.route("post") { predicateSpec ->
            predicateSpec
                .order(0)
                .isPostRequestToMcpEndpoint().and()
                .uri("no://op")
        }
        routesBuilder.route("get") { predicateSpec ->
            predicateSpec.isGetRequestToMcpEndpoint().uri("no://op")
        }
        routesBuilder.route("delete") { predicateSpec ->
            predicateSpec.isDeleteRequestToMcpEndpoint().uri("no://op")
        }
        return routesBuilder.build()
    }

    private fun PredicateSpec.isPostRequestToMcpEndpoint() =
        method(HttpMethod.POST).and().path(GatewayPolicy.MCP_ENDPOINT_PATH)

    private fun PredicateSpec.isGetRequestToMcpEndpoint() =
        method(HttpMethod.GET).and().path(GatewayPolicy.MCP_ENDPOINT_PATH)

    private fun PredicateSpec.isDeleteRequestToMcpEndpoint() =
        method(HttpMethod.DELETE).and().path(GatewayPolicy.MCP_ENDPOINT_PATH)
}
