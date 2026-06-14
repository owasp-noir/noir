#ifndef UserController_hpp
#define UserController_hpp

#include "oatpp/web/server/api/ApiController.hpp"
#include "oatpp/core/macro/codegen.hpp"

#include OATPP_CODEGEN_BEGIN(ApiController) //<- Begin Codegen

class UserController : public oatpp::web::server::api::ApiController {
public:
  UserController(OATPP_COMPONENT(std::shared_ptr<ObjectMapper>, objectMapper))
    : oatpp::web::server::api::ApiController(objectMapper)
  {}

public:

  // Metadata macro — must NOT be treated as a route.
  ENDPOINT_INFO(getUserById) {
    info->summary = "Get one User by userId";
  }
  ENDPOINT("GET", "users/{userId}", getUserById,
           PATH(Int32, userId)) {
    return createDtoResponse(Status::CODE_200, m_userService.getUserById(userId));
  }

  // POST with a JSON body DTO.
  ENDPOINT("POST", "users", createUser,
           BODY_DTO(Object<UserDto>, userDto)) {
    return createDtoResponse(Status::CODE_200, m_userService.createUser(userDto));
  }

  // Query param + header param (the header uses a name-override 3rd argument).
  ENDPOINT("GET", "users/search", searchUsers,
           QUERY(String, name),
           HEADER(String, token, "X-Auth-Token")) {
    return createResponse(Status::CODE_200, name);
  }

  // Multiple path params.
  ENDPOINT("DELETE", "users/{userId}/posts/{postId}", deletePost,
           PATH(Int32, userId),
           PATH(Int32, postId)) {
    return createResponse(Status::CODE_200, "ok");
  }

};

#include OATPP_CODEGEN_END(ApiController) //<- End Codegen

#endif /* UserController_hpp */
