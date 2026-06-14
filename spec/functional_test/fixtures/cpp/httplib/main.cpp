#include <httplib.h>

// Named-function handler resolved from the same file: its header read and
// repository call attach to the Delete endpoint.
void delete_user(const httplib::Request& req, httplib::Response& res)
{
    auto token = req.get_header_value("X-Token");
    repository_delete(req.path_params.at("id"));
    res.status = 204;
}

int main()
{
    httplib::Server svr;

    // Inline lambda handler with query + header + body params.
    svr.Get("/", [](const httplib::Request& req, httplib::Response& res) {
        auto q = req.get_param_value("q");
        auto auth = req.get_header_value("Authorization");
        res.set_content("ok", "text/plain");
    });

    // Named path parameter `:id` → {id}.
    svr.Get("/users/:id", [](const httplib::Request& req, httplib::Response& res) {
        auto id = req.path_params.at("id");
        res.set_content(id, "text/plain");
    });

    // POST with a JSON body read in the lambda.
    svr.Post("/users", [](const httplib::Request& req, httplib::Response& res) {
        auto data = req.body;
        res.status = 201;
    });

    // Named-function handler defined above.
    svr.Delete("/users/:id", delete_user);

    // Raw-string regex route — kept verbatim, no named params.
    svr.Get(R"(/files/(.*))", [](const httplib::Request& req, httplib::Response& res) {
        auto name = req.matches[1];
        res.set_content(name, "text/plain");
    });

    // PATCH route.
    svr.Patch("/settings", [](const httplib::Request& req, httplib::Response& res) {
        res.status = 200;
    });

    // A cpp-httplib CLIENT call must NOT be treated as a route.
    httplib::Client cli("http://example.com");
    auto external = cli.Get("/external");

    svr.listen("0.0.0.0", 8080);
    return 0;
}
