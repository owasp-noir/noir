package com.example.web;

import java.util.List;
import java.util.Map;
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
