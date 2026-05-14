#include <drogon/drogon.h>
#include <drogon/HttpController.h>

using namespace drogon;

class ApiController : public drogon::HttpController<ApiController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(ApiController::listUsers, "/api/users", Get);
    ADD_METHOD_TO(ApiController::createUser, "/api/users", Post);
    METHOD_LIST_END

    void warmup(const HttpRequestPtr &req) {
        if (listUsers(req)) {
            Noise::wrong();
        }
    }

    void listUsers(const HttpRequestPtr &req,
                   std::function<void(const HttpResponsePtr &)> &&callback) {
        auto users = UserService::list();
        auto resp = HttpResponse::newHttpJsonResponse(renderUsers(users));
        callback(resp);
    }

    void createUser(const HttpRequestPtr &req,
                    std::function<void(const HttpResponsePtr &)> &&callback) {
        auto body = req->getJsonObject();
        auto user = UserService::create(body);
        callback(makeCreatedResponse(user));
    }
};

int main() {
    app().registerHandler(
        "/ping",
        [](const HttpRequestPtr &req,
           std::function<void(const HttpResponsePtr &)> &&callback) {
            auto name = req->getParameter("name");
            auto resp = HttpResponse::newHttpResponse();
            callback(resp);
        },
        {Get});

    app().registerHandler(
        "/items/{id:int}",
        [](const HttpRequestPtr &req,
           std::function<void(const HttpResponsePtr &)> &&callback,
           int id) {
            auto item = ItemService::load(id);
            callback(HttpResponse::newHttpJsonResponse(renderItem(item)));
        },
        {Get, drogon::Delete});

    app().run();
    return 0;
}
