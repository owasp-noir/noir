#include <drogon/HttpController.h>
class C : public drogon::HttpController<C> {
 public:
  METHOD_LIST_BEGIN
  ADD_METHOD_VIA_REGEX(C::get, "^/drogon/([0-9]+)$", Get);
  METHOD_LIST_END
  void get(const HttpRequestPtr &req, std::function<void(const HttpResponsePtr &)> &&cb, int id);
};
