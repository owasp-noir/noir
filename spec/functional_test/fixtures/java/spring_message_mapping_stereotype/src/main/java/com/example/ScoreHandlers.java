package com.example;

import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.stereotype.Controller;

@Controller
abstract class BaseHandlers {
}

// @Controller on the superclass: Spring finds it up the hierarchy.
public class ScoreHandlers extends BaseHandlers {
    @MessageMapping("/score")
    public void score(String text) {
    }
}
