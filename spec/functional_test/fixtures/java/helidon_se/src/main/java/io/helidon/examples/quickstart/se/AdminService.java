package io.helidon.examples.quickstart.se;

import io.helidon.webserver.http.HttpRules;
import io.helidon.webserver.http.HttpService;

public class AdminService implements HttpService {

    private static final String STATUS_PATH = "/status";

    @Override
    public void routing(HttpRules rules) {
        rules.get(STATUS_PATH, (req, res) -> res.send("admin-ok"))
             .delete("/cache/{cacheId}", (req, res) -> res.send("cleared"));
    }
}
