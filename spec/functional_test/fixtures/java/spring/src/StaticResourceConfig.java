package com.test;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class StaticResourceConfig implements WebMvcConfigurer {
    private static final String ASSET_ROOT = "/assets";

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler(ASSET_ROOT + "/**", "/webjars/**")
                .addResourceLocations("classpath:/static/", "classpath:/META-INF/resources/webjars/");
    }
}
