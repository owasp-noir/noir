#include "crow.h"

// Mock server a unit test starts on localhost; the app never serves it.
void start_fake_server() {
    crow::SimpleApp fake;

    CROW_ROUTE(fake, "/fake/crow")([]() {
        return "fake";
    });
}
