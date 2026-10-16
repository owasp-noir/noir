#include "crow.h"

int main() {
    crow::SimpleApp app;

    CROW_ROUTE(app, "/real/crow")([]() {
        return "ok";
    });

    app.port(18080).run();
}
