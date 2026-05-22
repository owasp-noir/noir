package org.example.armeria;

import com.linecorp.armeria.common.HttpResponse;
import com.linecorp.armeria.common.HttpMethod;
import com.linecorp.armeria.common.HttpRequest;
import com.linecorp.armeria.server.HttpServiceWithRoutes;
import com.linecorp.armeria.server.Route;
import com.linecorp.armeria.server.Server;
import com.linecorp.armeria.server.ServiceRequestContext;
import com.linecorp.armeria.server.annotation.Get;
import com.linecorp.armeria.server.annotation.Post;
import java.util.Set;

public class TestParametersService {
    private static final String API_PREFIX = "/api";
    private static final String USERS_PATH = "/users";
    private static final String PRODUCTS_PATH = "/products";
    private static final String BULK_PATH = "/bulk/{bulkId}";
    private static final String OPEN_PATH = "/open/{openId}";

    public static void main(String[] args) {
        // Test .service() and .route() methods with path parameters
        Server
            .builder()
            .service(API_PREFIX + USERS_PATH + "/{userId}", new UserService())
            .service(API_PREFIX + PRODUCTS_PATH + "/{productId}/reviews", new ReviewService())
            .route().get("/items/{itemId}").build(new ItemService())
            .route().post("/orders/{orderId}/confirm").build(new OrderService())
            .route().put("/accounts/{accountId}/settings").build(new AccountService())
            .route().delete("/comments/{commentId}").build(new CommentService())
            .route().patch("/posts/{postId}/status").build(new PostService())
            .route().path(OPEN_PATH).build(new OpenService())
            .route().path(BULK_PATH).methods(HttpMethod.GET, HttpMethod.POST).build(new BulkService())
            .withRoute(builder -> builder.path("/insights/{insightId}")
                    .methods(HttpMethod.PUT, HttpMethod.DELETE)
                    .build(new InsightService()))
            .withRoute(builder -> builder.path("/wildcards/{wildcardId}")
                    .build(new WildcardService()))
            .service(Route.builder().path("/route-builder/{builderId}")
                    .methods(HttpMethod.GET, HttpMethod.POST)
                    .build(), new RouteBuilderService())
            .service(new CatalogRoutesService())
            .serviceUnder("/catalog-prefix", new CatalogRoutesService())
            .annotatedService("/mounted", new MountedAnnotatedService())
            .build()
            .start();
    }
}

class CatalogRoutesService implements HttpServiceWithRoutes {
    @Override
    public HttpResponse serve(ServiceRequestContext ctx, HttpRequest req) {
        return HttpResponse.of("ok");
    }

    @Override
    public Set<Route> routes() {
        return Set.of(
            Route.builder().get("/catalog/{catalogId}").build(),
            Route.builder().path("/catalog/{catalogId}/status").methods(HttpMethod.PATCH).build()
        );
    }
}
