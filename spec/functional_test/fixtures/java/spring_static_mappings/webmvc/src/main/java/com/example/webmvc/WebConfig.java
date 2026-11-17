package com.example.webmvc;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
@EnableWebMvc
public class WebConfig implements WebMvcConfigurer {
    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        registry.addResourceHandler("/assets/**")
            .addResourceLocations("classpath:/static/");
        registry.addResourceHandler(Paths.DOWNLOADS + "/**")
            .addResourceLocations(Paths.DOWNLOADS_LOCATION);
        registry.addResourceHandler("/pages/**")
            .addResourceLocations("/WEB-INF/pages/");
        // registry.addResourceHandler("/legacy/**").addResourceLocations("classpath:/public/");
    }
}
