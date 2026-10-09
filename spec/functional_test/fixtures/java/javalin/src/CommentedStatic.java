package com.example;

import io.javalin.Javalin;
import io.javalin.http.staticfiles.Location;

// A commented-out static mount serves nothing.
public class CommentedStatic {
    public static void configure() {
        Javalin.create(config -> {
            // config.staticFiles.add(files -> { files.hostedPath = "/retired"; });
        });
    }
}
