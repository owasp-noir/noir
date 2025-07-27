package com.test;
import javax.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/duplicate/parameter")
public class DuplicateParameter {

    @DeleteMapping(value = "{token}/test")
    public String Test(
        @Test @PathVariable(name = "token") String token
    ) {
        return "hello!";
    }
}