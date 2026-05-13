package controllers;

import play.libs.Json;
import play.mvc.Controller;
import play.mvc.Result;

public class AppController extends Controller {
    public Result create(String id) {
        String token = request().header("X-Token");
        User user = parseUser();
        User saved = userService().save(user, token);
        AuditLog.write("create");
        return ok(Json.toJson(saved));
    }

    public Result profile() {
        String profile = this.buildProfile();
        AuditLog.write(profile);
        return ok(profile);
    }

    private User parseUser() {
        return new User();
    }

    private UserService userService() {
        return new UserService();
    }

    private String buildProfile() {
        return "profile";
    }
}

class User {}

class UserService {
    User save(User user, String token) {
        return user;
    }
}

class AuditLog {
    static void write(String event) {}
}
