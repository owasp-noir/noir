package controllers;

import play.mvc.Controller;
import play.mvc.Result;
import play.libs.Json;
import com.fasterxml.jackson.databind.JsonNode;

public class HomeController extends Controller {
    public Result index() {
        return ok("Welcome to Play");
    }
}

class Users extends Controller {
    public Result list() {
        return ok("User list");
    }

    public Result show(Long id) {
        return ok("User " + id);
    }

    public Result create() {
        return ok("User created");
    }

    public Result update(Long id) {
        return ok("User " + id + " updated");
    }

    public Result delete(Long id) {
        return ok("User " + id + " deleted");
    }
}

class Search extends Controller {
    public Result search(String q, String filter) {
        return ok("Search results for " + q + " with filter " + filter);
    }
}

class Posts extends Controller {
    public Result show(Long userId, Long postId) {
        return ok("Post " + postId + " from user " + userId);
    }
}

class Items extends Controller {
    public Result list(String category, Integer page) {
        return ok("Items in category " + category + ", page " + page);
    }
}

class Files extends Controller {
    public Result download(String path) {
        return ok("Downloading file from " + path);
    }
}

class Upload extends Controller {
    public Result file() {
        return ok("File uploaded");
    }
}

class Api extends Controller {
    public Result protectedEndpoint() {
        String authToken = request().header("Authorization");
        String sessionId = request().cookie("session_id").value();
        return ok("Protected endpoint - Auth: " + authToken + ", Session: " + sessionId);
    }

    public Result postData() {
        String contentType = request().header("Content-Type");
        JsonNode json = request().body().asJson();
        return ok(Json.toJson(json));
    }
}

class Assets extends Controller {
    public Result at(String path, String file) {
        return ok("Asset " + path + "/" + file);
    }
}
