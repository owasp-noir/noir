package com.example.additive;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebConfig implements WebMvcConfigurer {
    private static final String FILES_PATTERN = "/files/**";
    private static final String DOCS_LOCATION = "classpath:/docs/";

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler(FILES_PATTERN)
            .setCachePeriod(0)
            .addResourceLocations(DOCS_LOCATION);
    }
}
