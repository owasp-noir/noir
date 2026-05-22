package com.test.annotations;

import org.springframework.web.bind.annotation.*;

@RequestMapping(method = RequestMethod.DELETE)
public @interface ExternalDelete {
    String value() default "";
}
