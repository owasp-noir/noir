package com.example;

import org.apache.wicket.protocol.http.WebApplication;
import org.apache.wicket.request.resource.IResource;
import org.apache.wicket.request.resource.ResourceReference;

public class WicketApplication extends WebApplication {
    @Override
    protected void init() {
        mountResource("/a-api", new ResourceReference("a-rest") {
            private final SharedRestResource resource = new SharedRestResource();

            @Override
            public IResource getResource() {
                return resource;
            }
        });
    }
}
