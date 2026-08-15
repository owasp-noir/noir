package com.example;

import io.dropwizard.Application;
import io.dropwizard.setup.Bootstrap;
import io.dropwizard.setup.Environment;

public class HelloApplication extends Application<HelloConfiguration> {
    public static void main(String[] args) throws Exception {
        new HelloApplication().run(args);
    }

    @Override
    public void initialize(Bootstrap<HelloConfiguration> bootstrap) {
    }

    @Override
    public void run(HelloConfiguration configuration, Environment environment) {
        environment.jersey().register(new com.example.api.SearchResource());
    }
}
