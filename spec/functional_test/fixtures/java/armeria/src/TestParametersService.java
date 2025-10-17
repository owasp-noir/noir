package org.example.armeria;

import com.linecorp.armeria.common.HttpResponse;
import com.linecorp.armeria.server.Server;
import com.linecorp.armeria.server.annotation.Get;
import com.linecorp.armeria.server.annotation.Post;

public class TestParametersService {
    public static void main(String[] args) {
        Server
            .builder()
            .service("/api/users/{userId}", new UserService())
            .service("/api/products/{productId}/reviews", new ReviewService())
            .route()
                .get("/items/{itemId}")
                .post("/orders/{orderId}/confirm")
                .put("/accounts/{accountId}/settings")
                .delete("/comments/{commentId}")
                .patch("/posts/{postId}/status")
            .build();
    }
}
