package com.example;

import static spark.Spark.*;

import java.util.HashMap;
import java.util.Map;

public class SparkApp {
    public static void main(String[] args) {
        get("/spark/hello", (req, res) -> "hi");
        get("spark/slashless", (req, res) -> "ok");

        // Not routes: a template-model Map.put with a `new` value, a JDBC
        // getter with a class literal, and unqualified put() calls inside a
        // double-brace HashMap initializer.
        Map<String, Object> templateMap = new HashMap<>();
        templateMap.put("isrecordacall", new Object());

        Row row = null;
        row.get("run_status", String.class);

        String uuid = "token";
        Map<String, Object> model = new HashMap<String, Object>() {{
            put("csrf", uuid);
            put("error", uuid);
        }};
    }

    interface Row {
        Object get(String name, Class<?> type);
    }
}
