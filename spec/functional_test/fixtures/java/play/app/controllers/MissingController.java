package controllers;

import play.mvc.Controller;
import play.mvc.Result;

public class MissingController extends Controller {

    public Result multipart() {
        // Should be form/multipart
        Object body = request().body().asMultipartFormData();
        return ok("multipart");
    }

    public Result bytes() {
        // Should be body/bytes
        byte[] b = request().body().asBytes();
        return ok("bytes");
    }

    public Result whitespace() {
        // Should be json
        request() . body() . asJson();
        return ok("json");
    }
}
