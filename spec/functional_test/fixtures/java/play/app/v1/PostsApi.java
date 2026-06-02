package v1;

import com.fasterxml.jackson.databind.JsonNode;
import play.mvc.Controller;
import play.mvc.Http;
import play.mvc.Result;

// Controller deliberately parked outside the conventional `controllers`
// package — Play resolves it by the fully-qualified name in `routes`.
// Regression guard: its header/body params must still be enriched.
public class PostsApi extends Controller {
    public Result create(Http.Request request) {
        String trace = request.header("X-Posts-Trace").orElse("none");
        JsonNode json = request.body().asJson();
        return ok("created");
    }
}
