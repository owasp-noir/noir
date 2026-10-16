#include <drogon/drogon.h>

using namespace drogon;

// Mock server a unit test starts on localhost; the app never serves it.
void start_fake_server() {
    app().registerHandler(
        "/fake/drogon",
        [](const HttpRequestPtr &req,
           std::function<void(const HttpResponsePtr &)> &&callback) {
            callback(HttpResponse::newHttpResponse());
        },
        {Get});
}
