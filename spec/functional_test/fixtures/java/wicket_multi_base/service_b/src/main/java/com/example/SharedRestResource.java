package com.example;

import org.apache.wicket.request.resource.IResource;
import org.wicketstuff.rest.annotations.MethodMapping;
import org.wicketstuff.rest.annotations.ResourcePath;

@ResourcePath("/b-scanned")
public class SharedRestResource implements IResource {
    @MethodMapping("/only-b")
    public String onlyB() {
        return "b";
    }
}
