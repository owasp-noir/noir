package demo;

import com.fasterxml.jackson.annotation.JsonRootName;
import org.springframework.web.bind.annotation.*;

// No UNWRAP_ROOT_VALUE in this module: @JsonRootName does not change reads.
@RestController
public class SessionsApi {
    @PostMapping("/sessions")
    public String login(@RequestBody SessionParam param) { return "ok"; }
}

@JsonRootName("session")
class SessionParam {
    public String email;
}
