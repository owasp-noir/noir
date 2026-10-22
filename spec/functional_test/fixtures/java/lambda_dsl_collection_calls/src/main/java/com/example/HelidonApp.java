package com.example;

import io.helidon.webserver.http.HttpRouting;
import java.util.HashMap;
import java.util.Map;

public class HelidonApp {
    static void routing(HttpRouting.Builder routing) {
        routing.get("/helidon/health", (req, res) -> res.send("OK"))
               .get("helidon/slashless", (req, res) -> res.send("ok"))
               .post("helidon/by-ref", HelidonApp::handle);
    }

    static void handle(Object req, Object res) {
    }

    // None of these are routes: a Map key, a JDBC column and a config key
    // that merely share the `put` / `get` verb names.
    static Map<String, String> encodings() {
        Map<String, String> result = new HashMap<>();
        result.put("br", "br");
        result.put("gzip", "gzip");
        return result;
    }

    static Object column(Row row, Config config) {
        config.get("db.url", String.class);
        return row.get("ID", Integer.class);
    }

    interface Row {
        Object get(String name, Class<?> type);
    }

    interface Config {
        Object get(String key, Class<?> type);
    }
}
