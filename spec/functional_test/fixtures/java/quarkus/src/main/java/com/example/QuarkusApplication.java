package com.example;

import io.quarkus.runtime.Startup;
import jakarta.ws.rs.ApplicationPath;
import jakarta.ws.rs.core.Application;

@Startup
@ApplicationPath("/q")
public class QuarkusApplication extends Application {
}
