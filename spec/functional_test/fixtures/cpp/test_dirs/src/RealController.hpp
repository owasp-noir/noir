#include "oatpp/web/server/api/ApiController.hpp"
#include "oatpp/core/macro/codegen.hpp"

#include OATPP_CODEGEN_BEGIN(ApiController)

class RealController : public oatpp::web::server::api::ApiController {
public:
  ENDPOINT("GET", "real/oatpp", realOatpp) {
    return createResponse(Status::CODE_200, "ok");
  }
};

#include OATPP_CODEGEN_END(ApiController)
