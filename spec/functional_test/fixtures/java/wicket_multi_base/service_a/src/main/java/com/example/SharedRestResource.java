package com.example;

import org.apache.wicket.request.resource.IResource;
import org.wicketstuff.rest.annotations.MethodMapping;
import org.wicketstuff.rest.annotations.ResourcePath;

@ResourcePath("/a-scanned")
public class SharedRestResource implements IResource {
    @MethodMapping("/only-a")
    public String onlyA() {
        return "a";
    }
}
