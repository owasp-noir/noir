#include <drogon/drogon.h>

using namespace drogon;

int main()
{
    // Multi-line registerHandler whose path carries a query-string constraint.
    app().registerHandler(
        "/search?q={}",
        [](const HttpRequestPtr &req,
           std::function<void(const HttpResponsePtr &)> &&callback) {
            auto keyword = req->getParameter("q");
            callback(HttpResponse::newHttpResponse());
        },
        {Get});

    /* Commented-out registration must be ignored:
    app().registerHandler("/ghost", &ghost, {Get});
    */

    app().run();
    return 0;
}
