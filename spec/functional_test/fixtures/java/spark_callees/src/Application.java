package com.example;

import static spark.Spark.*;

public class Application {
    public static void main(String[] args) {
        post("/users", (req, res) -> {
            String name = req.queryParams("name");
            String saved = UserService.save(name);
            AuditLog.write(saved);
            res.status(201);
            return saved;
        });

        get("/profile", (req, res) -> {
            String built = buildProfile();
            AuditLog.write(built);
            return built;
        });

        get("/legacy", (req, res) -> {
            AuditLog.write("legacy");
            return getLegacy().toString();
        });
    }

    static String buildProfile() {
        return "profile";
    }

    static String getLegacy() {
        return "legacy";
    }
}
