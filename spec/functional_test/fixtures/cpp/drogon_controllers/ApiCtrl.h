#pragma once
#include <drogon/HttpController.h>

using namespace drogon;

namespace app
{
namespace v2
{
class ApiCtrl : public drogon::HttpController<ApiCtrl>
{
  public:
    METHOD_LIST_BEGIN
    // Relative path → prefixed with /app/v2/ApiCtrl
    METHOD_ADD(ApiCtrl::root, "", Get);
    // Multi-line macro with a path param and a trailing filter argument.
    METHOD_ADD(ApiCtrl::show,
               "/show/{id}",
               Get,
               "app::AuthFilter");
    // Absolute path, two methods.
    ADD_METHOD_TO(ApiCtrl::ping, "/ping", Get, Post);
    // Absolute regex path.
    ADD_METHOD_VIA_REGEX(ApiCtrl::legacy, "/legacy/(.*)", Get);
    // Regex with `?` metacharacters must be preserved verbatim (not treated
    // as a query-string separator).
    ADD_METHOD_VIA_REGEX(ApiCtrl::grouped, "/grp/(?:a|b)/(.*)?", Get);
    // Brace-wrapped verb list `{Post, Options}` — a common real-world form.
    METHOD_ADD(ApiCtrl::brace, "/brace", {Post, Options});
    METHOD_LIST_END

    void root(const HttpRequestPtr &req,
              std::function<void(const HttpResponsePtr &)> &&callback)
    {
        auto resp = HttpResponse::newHttpResponse();
        callback(resp);
    }

    void show(const HttpRequestPtr &req,
              std::function<void(const HttpResponsePtr &)> &&callback)
    {
        auto user = UserService::find(req->getParameter("q"));
        callback(HttpResponse::newHttpJsonResponse(renderUser(user)));
    }

    void ping(const HttpRequestPtr &req,
              std::function<void(const HttpResponsePtr &)> &&callback)
    {
        callback(HttpResponse::newHttpResponse());
    }

    void legacy(const HttpRequestPtr &req,
                std::function<void(const HttpResponsePtr &)> &&callback)
    {
        callback(HttpResponse::newHttpResponse());
    }

    void grouped(const HttpRequestPtr &req,
                 std::function<void(const HttpResponsePtr &)> &&callback)
    {
        callback(HttpResponse::newHttpResponse());
    }

    void brace(const HttpRequestPtr &req,
               std::function<void(const HttpResponsePtr &)> &&callback)
    {
        callback(HttpResponse::newHttpResponse());
    }
};
}  // namespace v2
}  // namespace app
