#include "crow.h"

int main() {
    crow::SimpleApp app;

    CROW_ROUTE(app, "/users/<int>")
    ([](const crow::request& req, int id) {
        auto user = UserService::load(id);
        AuditLog::write("show", user);
        return crow::response(serializeUser(user));
    });

    CROW_ROUTE(app, "/users").methods("POST"_method, "PUT"_method)
    ([](const crow::request& req) {
        auto payload = parseJson(req.body);
        UserService service;
        auto user = service.save(payload);
        return crow::response(201, renderUser(user));
    });

    CROW_BP_ROUTE(api, "/search")
    .methods("GET"_method)
    ([](const crow::request& request) {
        auto q = request.url_params.get("q");
        auto token = request.get_header_value("X-Token");
        // Ignored::comment();
        auto text = "Ignored::string()";
        if (FeatureFlags::enabled("search")) {
            return crow::response(SearchService::run(q, token));
        }
        return crow::response(404);
    });

    app.port(18080).multithreaded().run();
    return 0;
}
