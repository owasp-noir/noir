package org.example.armeria;

import com.linecorp.armeria.common.HttpResponse;
import com.linecorp.armeria.server.Server;
import com.linecorp.armeria.server.annotation.Get;
import com.linecorp.armeria.server.annotation.Post;

public class TestParametersService {
    public static void main(String[] args) {
        // Test .service() and .route() methods with path parameters
        Server
            .builder()
            .service("/api/users/{userId}", new UserService())
            .service("/api/products/{productId}/reviews", new ReviewService())
            .route().get("/items/{itemId}").build(new ItemService())
            .route().post("/orders/{orderId}/confirm").build(new OrderService())
            .route().put("/accounts/{accountId}/settings").build(new AccountService())
            .route().delete("/comments/{commentId}").build(new CommentService())
            .route().patch("/posts/{postId}/status").build(new PostService())
            .build()
            .start();
    }
}
