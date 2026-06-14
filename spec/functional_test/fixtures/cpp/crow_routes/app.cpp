#include "crow.h"
#include "crow/middlewares/cookie_parser.h"

int main()
{
    crow::App<crow::CookieParser> app;

    // Static route — must keep only its own body param, not absorb the params
    // of the route_dynamic registration that follows it.
    CROW_ROUTE(app, "/static")
    ([](const crow::request& req) {
        return crow::response(req.body);
    });

    // Runtime-string dynamic route.
    app.route_dynamic("/dynamic")
    ([](const crow::request& req) {
        auto foo = req.url_params.get("foo");
        return crow::response(200);
    });

    // url_params list/dict accessors.
    CROW_ROUTE(app, "/list")
    ([](const crow::request& req) {
        auto items = req.url_params.get_list("items");
        auto meta = req.url_params.get_dict("meta");
        return crow::response(200);
    });

    // Cookie read through the CookieParser middleware context.
    CROW_ROUTE(app, "/cookie")
    ([&](const crow::request& req) {
        auto& ctx = app.get_context<crow::CookieParser>(req);
        auto sid = ctx.get_cookie("session");
        return crow::response(200);
    });

    // Websocket upgrade endpoint.
    CROW_WEBSOCKET_ROUTE(app, "/ws")
      .onmessage([&](crow::websocket::connection& conn, const std::string& data, bool) {
          conn.send_text(data);
      });

    // Single-level blueprint: prefix "admin" → /admin/dashboard.
    crow::Blueprint admin_bp("admin");
    CROW_BP_ROUTE(admin_bp, "/dashboard")
    ([]() { return crow::response(200); });
    app.register_blueprint(admin_bp);

    // Nested blueprint: v2_bp ("v2") registered under api_bp ("api") →
    // the route resolves to /api/v2/status.
    crow::Blueprint api_bp("api");
    crow::Blueprint v2_bp("v2");
    CROW_BP_ROUTE(v2_bp, "/status")
    ([]() { return crow::response(200); });
    api_bp.register_blueprint(v2_bp);
    app.register_blueprint(api_bp);

    /* Commented-out route must be ignored:
    CROW_ROUTE(app, "/ghost")
    ([]() {
        auto secret = req.url_params.get("secret");
        return "no";
    });
    */

    app.port(18080).run();
}
