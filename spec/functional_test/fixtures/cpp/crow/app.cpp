#include "crow.h"

int main() {
    crow::SimpleApp app;

    CROW_ROUTE(app, "/")([]() {
        return "Hello World";
    });

    CROW_ROUTE(app, "/update").methods("POST"_method)
    ([](const crow::request& req) {
        auto name = req.url_params.get("name");
        auto token = req.get_header_value("X-Token");
        return crow::response(200, req.body);
    });

    CROW_ROUTE(app, "/user/<int>/<string>")
    ([](int id, std::string name) {
        return crow::response(200);
    });

    CROW_ROUTE(app, "/search")
    ([](const crow::request& req) {
        auto q = req.url_params.get("q");
        return crow::response(200);
    });

    app.port(18080).multithreaded().run();
    return 0;
}
