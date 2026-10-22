#include <drogon/drogon.h>

using namespace drogon;

int main() {
    app().registerHandler(
        "/real/drogon",
        [](const HttpRequestPtr &req,
           std::function<void(const HttpResponsePtr &)> &&callback) {
            callback(HttpResponse::newHttpResponse());
        },
        {Get});
    app().run();
}
