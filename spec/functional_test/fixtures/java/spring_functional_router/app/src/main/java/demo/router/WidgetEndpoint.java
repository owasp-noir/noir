package demo.router;

import static org.springframework.web.reactive.function.server.RequestPredicates.path;

// Halo-style custom endpoints: mounted under /apis/<group>/<version>.
public class WidgetEndpoint implements CustomEndpoint {

    @Override
    public RouterFunction<ServerResponse> endpoint() {
        return SpringdocRouteBuilder.route()
            .GET("widgets/{name}", this::get, builder -> builder.operationId("GetWidget"))
            .PUT("widgets/{name}/enable", this::enable)
            .build();
    }

    @Override
    public GroupVersion groupVersion() {
        return GroupVersion.parseAPIVersion("uc.api.demo.run/v1alpha1");
    }
}

class GadgetEndpoint implements CustomEndpoint {
    static final String GROUP = "demo.run";

    public GroupVersion groupVersion() {
        return GroupVersion.parseAPIVersion("console.api." + GROUP + "/v2");
    }

    public RouterFunction<ServerResponse> endpoint() {
        return route().nest(path("/gadgets"), b -> b.GET("/{id}", this::get)).build();
    }
}

// Not a CustomEndpoint: keeps its path as written.
class PlainRouter {
    public RouterFunction<ServerResponse> router() {
        return route().GET("/plain", this::get).build();
    }
}
