#include "oatpp/web/server/api/ApiController.hpp"
#include "oatpp/core/macro/codegen.hpp"

#include OATPP_CODEGEN_BEGIN(ApiController)

// Mock controller a unit test mounts on a throwaway router.
class FakeController : public oatpp::web::server::api::ApiController {
public:
  ENDPOINT("GET", "fake/oatpp", fakeOatpp) {
    return createResponse(Status::CODE_200, "fake");
  }
};

#include OATPP_CODEGEN_END(ApiController)
