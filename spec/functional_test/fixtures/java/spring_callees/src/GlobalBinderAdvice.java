package com.test;

import org.springframework.web.bind.WebDataBinder;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.InitBinder;

// Applies to every controller in the project.
@ControllerAdvice
public class GlobalBinderAdvice {
    @InitBinder
    public void disallowSecret(WebDataBinder dataBinder) {
        dataBinder.setDisallowedFields("secret");
    }
}
