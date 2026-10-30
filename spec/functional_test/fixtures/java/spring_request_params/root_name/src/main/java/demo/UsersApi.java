package demo;

import com.fasterxml.jackson.annotation.JsonRootName;
import com.fasterxml.jackson.annotation.JsonUnwrapped;
import org.springframework.web.bind.annotation.*;

@RestController
public class UsersApi {
    @PostMapping("/users/login")
    public String login(@RequestBody LoginParam param) { return "ok"; }

    @PostMapping("/articles")
    public String article(@RequestBody NewArticleParam param) { return "ok"; }

    @PostMapping("/wrapped")
    public String wrapped(@RequestBody OnlyUnwrapped param) { return "ok"; }

    @PostMapping("/namespaced")
    public String namespaced(@RequestBody Namespaced param) { return "ok"; }
}

class Inner {
    public String innerField;
}

@JsonRootName("outer")
class OnlyUnwrapped {
    @JsonUnwrapped(prefix = "p_")
    public Inner inner;
}

@JsonRootName(namespace = "ns", value = "named")
class Namespaced {
    public String a;
}

@JsonRootName("user")
class LoginParam {
    public String email;
    public String password;
}

class NewArticleParam {
    public String title;
}
