package com.example.web;

import java.util.List;
import java.util.Map;
import com.fasterxml.jackson.annotation.JsonIgnore;
import javax.servlet.http.HttpServletRequest;
import org.springframework.http.HttpHeaders;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;

@RestController
class MapParamController {
    @DeleteMapping("/series")
    String series(@RequestParam(name = "keys", required = false) String keysStr,
                  @RequestParam MultiValueMap<String, String> params) {
        return keys(keysStr, params).toString();
    }

    @GetMapping("/trace")
    String trace(@RequestHeader HttpHeaders headers) {
        return headers.getFirst("X-Trace");
    }

    @GetMapping("/fwd")
    String fwd(HttpServletRequest request) {
        return scheme(request);
    }

    @PutMapping("/pwd")
    String pwd(@RequestBody Map<String, String> params) {
        return params.get("oldPassword") + params.get("newPassword");
    }

    @PostMapping("/mvm")
    String mvm(@RequestBody MultiValueMap<String, String> form) {
        return form.getFirst("mk");
    }

    @PostMapping("/reassigned")
    String reassigned(@RequestBody Map<String, String> body) {
        body = Map.of();
        return body.get("notInput");
    }

    record Pair(@JsonIgnore String a, String b) {}

    @PostMapping("/pair")
    String pair(@RequestBody Pair pair) {
        return pair.b();
    }

    @PutMapping("/entity")
    String entity(@RequestBody IgnoredEntity entity) {
        return entity.toString();
    }

    @GetMapping("/entity")
    String entityQuery(IgnoredEntity entity) {
        return entity.toString();
    }

    private List<String> keys(String keysStr, MultiValueMap<String, String> params) {
        return params.get("key") != null ? params.get("key") : List.of(keysStr);
    }

    private String scheme(HttpServletRequest req) {
        return req.getHeader("X-Forwarded-Proto");
    }
}
