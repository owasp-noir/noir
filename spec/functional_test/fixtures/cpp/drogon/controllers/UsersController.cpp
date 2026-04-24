#include <drogon/HttpController.h>

using namespace drogon;

class UsersController : public drogon::HttpController<UsersController> {
public:
    PATH_LIST_BEGIN
    PATH_ADD("/api/users", Get, Post);
    PATH_ADD("/api/users/{id}", Get, Put, Delete);
    PATH_ADD("/api/users/{id}/profile", Get);
    PATH_LIST_END

    void listUsers(const HttpRequestPtr &req,
                   std::function<void(const HttpResponsePtr &)> &&callback) {
        auto search = req->getParameter("search");
        auto limit = req->getParameter("limit");
        auto resp = HttpResponse::newHttpResponse();
        callback(resp);
    }

    void createUser(const HttpRequestPtr &req,
                    std::function<void(const HttpResponsePtr &)> &&callback) {
        auto body = req->getJsonObject();
        auto resp = HttpResponse::newHttpResponse();
        callback(resp);
    }

    void getUser(const HttpRequestPtr &req,
                 std::function<void(const HttpResponsePtr &)> &&callback,
                 const std::string &id) {
        auto resp = HttpResponse::newHttpResponse();
        callback(resp);
    }

    void updateUser(const HttpRequestPtr &req,
                    std::function<void(const HttpResponsePtr &)> &&callback,
                    const std::string &id) {
        auto body = req->getJsonObject();
        auto resp = HttpResponse::newHttpResponse();
        callback(resp);
    }

    void deleteUser(const HttpRequestPtr &req,
                    std::function<void(const HttpResponsePtr &)> &&callback,
                    const std::string &id) {
        auto resp = HttpResponse::newHttpResponse();
        callback(resp);
    }

    void getProfile(const HttpRequestPtr &req,
                    std::function<void(const HttpResponsePtr &)> &&callback,
                    const std::string &id) {
        auto token = req->getHeader("X-API-Token");
        auto resp = HttpResponse::newHttpResponse();
        callback(resp);
    }
};
