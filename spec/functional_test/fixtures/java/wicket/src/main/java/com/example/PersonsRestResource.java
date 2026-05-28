package com.example;

import org.apache.wicket.request.resource.IResource;
import org.wicketstuff.rest.annotations.MethodMapping;
import org.wicketstuff.rest.annotations.ResourcePath;
import org.wicketstuff.restutils.http.HttpMethod;

@ResourcePath("/scanned")
public class PersonsRestResource implements IResource {
    @MethodMapping("/persons")
    public String listPeople() {
        return "[]";
    }

    @MethodMapping(value = "/persons/{personId:\\d+}", httpMethod = HttpMethod.DELETE)
    public void deletePerson(int personId) {
    }
}
