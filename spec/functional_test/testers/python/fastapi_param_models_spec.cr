require "../../func_spec.cr"

# Request models resolved the way FastAPI and Pydantic read them:
#
#   * `from app.schema import Registration` re-exported by
#     `from .user import *` in the package `__init__.py`, with a base
#     model in another module whose `alias_generator` camelizes field
#     names (an explicit `Field(alias=...)` still wins). `Registration`
#     is not a `str` query parameter for containing the letters "str".
#   * `form: LoginForm = Depends()` — FastAPI calls the class, so its
#     `__init__` `Form()` parameters are the request's.
#   * `q: Annotated[FeedQuery, Query()]` — a query parameter model.
#   * A class-based view's `Depends(...)` class attributes (its own and a
#     base class's) contribute their dependency functions' parameters,
#     and a router prefix's `{group_slug}` binds `Path(...)` as a path
#     parameter rather than a query one.
expected_endpoints = [
  Endpoint.new("/register", "POST", [
    Param.new("fullName", "", "json"),
    Param.new("passwordConfirm", "", "json"),
    Param.new("mail", "", "json"),
  ]),
  Endpoint.new("/token", "POST", [
    Param.new("username", "", "form"),
    Param.new("remember_me", "false", "form"),
  ]),
  Endpoint.new("/feed", "GET", [
    Param.new("includeNotes", "true", "query"),
    Param.new("tz", "", "query"),
  ]),
  Endpoint.new("/groups/{group_slug}/items/{item_id}", "GET", [
    Param.new("page", "1", "query"),
    Param.new("accept-language", "", "header"),
    Param.new("group_slug", "", "path"),
    Param.new("item_id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/python/fastapi_param_models/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
