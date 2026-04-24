#include <drogon/drogon.h>

using namespace drogon;

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

    app().registerHandler(
        "/submit",
        [](const HttpRequestPtr &req,
           std::function<void(const HttpResponsePtr &)> &&callback) {
            auto body = req->getJsonObject();
            auto resp = HttpResponse::newHttpResponse();
            callback(resp);
        },
        {Post});

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

    app().run();
    return 0;
}
