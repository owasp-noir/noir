#ifndef StaticController_hpp
#define StaticController_hpp

#include "oatpp/web/server/api/ApiController.hpp"
#include "oatpp/core/macro/codegen.hpp"

#include OATPP_CODEGEN_BEGIN(ApiController) //<- Begin Codegen

class StaticController : public oatpp::web::server::api::ApiController {
public:
  StaticController(OATPP_COMPONENT(std::shared_ptr<ObjectMapper>, objectMapper))
    : oatpp::web::server::api::ApiController(objectMapper)
  {}

public:

  // Async endpoint: path placeholder mined, params declared in the class.
  ENDPOINT_ASYNC("GET", "room/{roomId}", ChatHTML) {
    ENDPOINT_ASYNC_INIT(ChatHTML)
    Action act() override {
      return _return(controller->createResponse(Status::CODE_200, "html"));
    }
  };

  // Root async endpoint.
  ENDPOINT_ASYNC("GET", "/", Root) {
    ENDPOINT_ASYNC_INIT(Root)
    Action act() override {
      return _return(controller->createResponse(Status::CODE_200, "root"));
    }
  };

  // Non-literal path (runtime expression) — must be skipped, not guessed.
  ENDPOINT_ASYNC("GET", m_appConfig->statisticsUrl, Stats) {
    ENDPOINT_ASYNC_INIT(Stats)
    Action act() override {
      return _return(controller->createResponse(Status::CODE_200, "stats"));
    }
  };

};

#include OATPP_CODEGEN_END(ApiController) //<- End Codegen

#endif /* StaticController_hpp */
