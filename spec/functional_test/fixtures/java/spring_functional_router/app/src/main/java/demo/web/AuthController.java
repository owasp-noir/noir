package demo.web;

import demo.annotation.AnonymousPostMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/auth")
public class AuthController {
    @AnonymousPostMapping(value = "/login")
    public String login() { return "token"; }

    @GetMapping("/info")
    public String info() { return "me"; }
}
