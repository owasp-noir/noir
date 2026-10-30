package demo;

import com.fasterxml.jackson.annotation.JsonRootName;
import org.springframework.web.bind.annotation.*;

@RestController
public class UsersApi {
    @PostMapping("/users/login")
    public String login(@RequestBody LoginParam param) { return "ok"; }

    @PostMapping("/articles")
    public String article(@RequestBody NewArticleParam param) { return "ok"; }
}

@JsonRootName("user")
class LoginParam {
    public String email;
    public String password;
}

class NewArticleParam {
    public String title;
}
