package com.example;

import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

// Two levels down: @Realtime -> @SocketController -> @Controller.
@Retention(RetentionPolicy.RUNTIME)
@SocketController
public @interface Realtime {
}
