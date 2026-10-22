package com.example.other;

import com.acme.web.Router;
import com.acme.web.HttpRequest;
import java.util.HashMap;
import java.util.Map;

// Names a `Router` of another framework and makes client calls / map writes
// whose first argument is a "/" string. None of it is a Vert.x route.
public class OtherRouterClient {
  private final Map<String, Object> cache = new HashMap<>();

  public void run(Router router) {
    HttpRequest.GET("/fake/client-call");
    Request.Post("/fake/fluent");
    cache.put("/fake/cache", 1);
  }
}
