package org.example.armeria;

import com.linecorp.armeria.common.HttpResponse;
import com.linecorp.armeria.server.annotation.Get;
import com.linecorp.armeria.server.annotation.Header;
import com.linecorp.armeria.server.annotation.Param;
import com.linecorp.armeria.server.annotation.Post;
import com.linecorp.armeria.server.annotation.RequestObject;

public class AnnotatedService {
    private final UserService service = new UserService();

    @Post("/annotated/users/{userId}")
    public HttpResponse createUser(@Param String userId,
                                   @RequestObject User user,
                                   @Header("Content-Type") String contentType) {
        validate(userId);
        service.save(user);
        AuditLog.write("create");
        return HttpResponse.of("created");
    }

    @Get("/annotated/users/profile")
    public HttpResponse profile() {
        String profile = this.buildProfile();
        AuditLog.write(profile);
        return HttpResponse.of(profile);
    }

    private void validate(String userId) {}

    private String buildProfile() {
        return "profile";
    }

    public static class User {
        public String name;
        public String email;
    }
}

class UserService {
    void save(AnnotatedService.User user) {}
}

class AuditLog {
    static void write(String event) {}
}
