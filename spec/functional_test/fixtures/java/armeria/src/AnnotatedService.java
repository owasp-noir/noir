package org.example.armeria;

import com.linecorp.armeria.common.HttpResponse;
import com.linecorp.armeria.server.annotation.Get;
import com.linecorp.armeria.server.annotation.Post;
import com.linecorp.armeria.server.annotation.Put;
import com.linecorp.armeria.server.annotation.Delete;
import com.linecorp.armeria.server.annotation.Default;
import com.linecorp.armeria.server.annotation.Patch;
import com.linecorp.armeria.server.annotation.Head;
import com.linecorp.armeria.server.annotation.Options;
import com.linecorp.armeria.server.annotation.Param;
import com.linecorp.armeria.server.annotation.Header;
import com.linecorp.armeria.server.annotation.Path;
import com.linecorp.armeria.server.annotation.PathPrefix;
import com.linecorp.armeria.server.annotation.RequestObject;

public class AnnotatedService {

    @Get("/annotated/users")
    public HttpResponse getUsers(@Param("page") int page, @Param("limit") @Default("25") int limit) {
        return HttpResponse.of("users");
    }

    @Get("/annotated/users/{userId}")
    public HttpResponse getUser(@Param String userId, @Header("Authorization") String auth) {
        return HttpResponse.of("user");
    }

    @Post("/annotated/users")
    public HttpResponse createUser(@RequestObject User user, @Header("Content-Type") String contentType) {
        return HttpResponse.of("created");
    }

    @Put("/annotated/users/{userId}")
    public HttpResponse updateUser(@Param String userId, @RequestObject User user) {
        return HttpResponse.of("updated");
    }

    @Delete("/annotated/users/{userId}")
    public HttpResponse deleteUser(@Param String userId, @Header("X-Request-Id") String requestId) {
        return HttpResponse.of("deleted");
    }

    @Patch("/annotated/users/{userId}/status")
    public HttpResponse patchUserStatus(@Param String userId, @Param("status") String status) {
        return HttpResponse.of("patched");
    }

    @Get("/annotated/search")
    public HttpResponse search(@Param("q") String query, @Param("category") String category, @Header("Accept-Language") String lang) {
        return HttpResponse.of("search");
    }

    @Head("/annotated/health")
    public HttpResponse healthCheck() {
        return HttpResponse.of("");
    }

    @Options("/annotated/cors")
    public HttpResponse corsOptions(@Header("Origin") String origin) {
        return HttpResponse.of("");
    }

    // Rest-path capture: `{*filePath}` binds the remainder of the path to
    // the `filePath` path variable — not a query parameter, and the name
    // must not carry the leading asterisk.
    @Get("/annotated/files/{*filePath}")
    public HttpResponse serveFile(@Param String filePath) {
        return HttpResponse.of("file");
    }

    // Inner class for RequestObject
    public static class User {
        public String name;
        public String email;
    }
}

@PathPrefix(PrefixedAnnotatedService.PREFIX)
class PrefixedAnnotatedService {
    static final String PREFIX = "/annotated/prefix";
    static final String REPORTS = "/reports";

    static final class Headers {
        static final String TRACE = "X-Trace";
    }

    @Get
    @Path(REPORTS + "/{reportId}")
    public HttpResponse getReport(@Param String reportId, @Header(Headers.TRACE) String trace) {
        return HttpResponse.of("report");
    }

    @Post
    @Path({"/submit", "/submit-alt"})
    public HttpResponse submit() {
        return HttpResponse.of("submit");
    }
}

class MountedAnnotatedService {
    @Get("/details/{detailId}")
    public HttpResponse detail(@Param String detailId) {
        return HttpResponse.of("detail");
    }

    @Post("/create")
    public HttpResponse create(@RequestObject MountedBody body) {
        return HttpResponse.of("create");
    }

    public static class MountedBody {
        public String title;
    }
}
