package com.example.api;

import io.dropwizard.Application;
import io.dropwizard.auth.AuthDynamicFeature;
import io.dropwizard.auth.basic.BasicCredentialAuthFilter;
import io.dropwizard.setup.Environment;

public class AuthApplication extends Application<AuthConfiguration> {
    @Override
    public void run(AuthConfiguration configuration, Environment environment) {
        environment.jersey().register(new AuthDynamicFeature(new BasicCredentialAuthFilter.Builder<User>().buildAuthFilter()));
        environment.jersey().register(new SessionResource());
    }
}
