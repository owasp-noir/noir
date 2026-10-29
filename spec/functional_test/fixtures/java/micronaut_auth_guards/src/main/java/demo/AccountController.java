package demo;

import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;
import io.micronaut.security.annotation.Secured;
import io.micronaut.security.rules.SecurityRule;

@Secured(SecurityRule.IS_AUTHENTICATED)
@Controller("/account")
public class AccountController {
    @Get
    public String me() { return "me"; }

    @Get("/public")
    @Secured(SecurityRule.IS_ANONYMOUS)
    public String pub() { return "pub"; }
}
