package com.example;

import static com.example.Commons.*;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

// The enclosing class declares its own BASE, which shadows the wildcard
// import of Commons.BASE inside the class body (the nested resource sees
// "/local"); ADMIN only exists through the import.
public class LocalResource {
    public static final String BASE = "/local";

    @Path(BASE)
    public static class Inner {
        @GET
        @Path("/m")
        public String m() {
            return "ok";
        }

        @GET
        @Path(ADMIN + "/o")
        public String o() {
            return "ok";
        }
    }
}
