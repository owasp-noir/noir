package org.example.armeria;

import com.linecorp.armeria.common.HttpResponse;
import com.linecorp.armeria.server.annotation.Get;
import com.linecorp.armeria.server.annotation.Post;
import com.linecorp.armeria.server.annotation.Put;
import com.linecorp.armeria.server.annotation.Delete;
import com.linecorp.armeria.server.annotation.Patch;
import com.linecorp.armeria.server.annotation.Head;
import com.linecorp.armeria.server.annotation.Options;
import com.linecorp.armeria.server.annotation.Param;
import com.linecorp.armeria.server.annotation.Header;
import com.linecorp.armeria.server.annotation.RequestObject;

public class AnnotatedService {

    @Get("/annotated/users")
    public HttpResponse getUsers(@Param("page") int page, @Param("limit") int limit) {
        return HttpResponse.of("users");
    }

    @Get("/annotated/users/{userId}")
    public HttpResponse getUser(@Param String userId, @Header("Authorization") String auth) {
        return HttpResponse.of("user");
    }

    @Post("/annotated/users")
    public HttpResponse createUser(@RequestObject User user, @Header("Content-Type") String contentType) {
        return HttpResponse.of("created");
    }

    @Put("/annotated/users/{userId}")
    public HttpResponse updateUser(@Param String userId, @RequestObject User user) {
        return HttpResponse.of("updated");
    }

    @Delete("/annotated/users/{userId}")
    public HttpResponse deleteUser(@Param String userId, @Header("X-Request-Id") String requestId) {
        return HttpResponse.of("deleted");
    }

    @Patch("/annotated/users/{userId}/status")
    public HttpResponse patchUserStatus(@Param String userId, @Param("status") String status) {
        return HttpResponse.of("patched");
    }

    @Get("/annotated/search")
    public HttpResponse search(@Param("q") String query, @Param("category") String category, @Header("Accept-Language") String lang) {
        return HttpResponse.of("search");
    }

    @Head("/annotated/health")
    public HttpResponse healthCheck() {
        return HttpResponse.of("");
    }

    @Options("/annotated/cors")
    public HttpResponse corsOptions(@Header("Origin") String origin) {
        return HttpResponse.of("");
    }

    // Inner class for RequestObject
    public static class User {
        public String name;
        public String email;
    }
}
