package demo;

import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;
import io.micronaut.security.annotation.Secured;
import io.micronaut.security.rules.SecurityRule;

@Secured(SecurityRule.IS_ANONYMOUS)
@Controller("/login")
public class LoginAuthController {
    @Get("/auth")
    public String auth() { return "form"; }

    @Get("/elsewhere")
    @Secured(SecurityRule.IS_AUTHENTICATED)
    public String elsewhere() { return "in"; }
}
