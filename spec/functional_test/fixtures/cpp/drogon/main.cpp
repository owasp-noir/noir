#include <drogon/drogon.h>

using namespace drogon;

void namedSearchHandler(const HttpRequestPtr &req,
                        std::function<void(const HttpResponsePtr &)> &&callback) {
    auto q = req->getParameter("q");
    auto resp = HttpResponse::newHttpResponse();
    callback(resp);
}

int main() {
    app().registerHandler(
        "/ping",
        [](const HttpRequestPtr &req,
           std::function<void(const HttpResponsePtr &)> &&callback) {
            auto name = req->getParameter("name");
            auto age = req->getParameter("age");
            auto resp = HttpResponse::newHttpResponse();
            callback(resp);
        },
        {Get});

    // No method list: Drogon accepts GET. Must not borrow /submit's {Post}.
    app().registerHandler(
        "/no-methods",
        [](const HttpRequestPtr &req,
           std::function<void(const HttpResponsePtr &)> &&callback) {
            auto dflt = req->getParameter("dflt");
            callback(HttpResponse::newHttpResponse());
        });

    app().registerHandler(
        "/submit",
        [](const HttpRequestPtr &req,
           std::function<void(const HttpResponsePtr &)> &&callback) {
            auto body = req->getJsonObject();
            auto resp = HttpResponse::newHttpResponse();
            callback(resp);
        },
        {Post});

    // Named handler, no method list: must not borrow the next lambda.
    app().registerHandler("/named-default", &namedSearchHandler);

    app().registerHandler(
        "/items/{id:int}",
        [](const HttpRequestPtr &req,
           std::function<void(const HttpResponsePtr &)> &&callback,
           int id) {
            auto auth = req->getHeader("Authorization");
            auto session = req->getCookie("session");
            auto resp = HttpResponse::newHttpResponse();
            callback(resp);
        },
        {Get, Delete});

    app().registerHandler("/named", &namedSearchHandler, {Get});

    // Filters before the verb, and a typed constraint list.
    app().registerHandler("/filtered", &namedSearchHandler, {"LoginFilter", Delete});
    app().registerHandler("/typed", &namedSearchHandler, std::vector<internal::HttpConstraint>{Patch});

    app().run();
    return 0;
}
