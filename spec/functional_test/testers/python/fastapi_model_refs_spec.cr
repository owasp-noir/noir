require "../../func_spec.cr"

# Pydantic body models named the ways real projects name them:
#
#   * `class ItemCreate(ItemBase): pass` inherits every field.
#   * A base imported under an alias (`Owned as OwnedBase`), through its
#     module (`base.Owned`), or as a generic (`Paged[int]`) still
#     contributes its fields; a base cycle stops instead of looping.
#   * A handler annotated `base.Owned` or with an import alias reads the
#     model's fields.
#   * Body model fields are JSON; `Annotated[Model, Form()]` is a form
#     model whose fields are form fields, and `File()` / `Form()`
#     parameters stay form.
expected_endpoints = [
  Endpoint.new("/items", "POST", [
    Param.new("title", "", "json"),
  ]),
  Endpoint.new("/notes", "POST", [
    Param.new("owner_id", "", "json"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/tags", "POST", [
    Param.new("owner_id", "", "json"),
    Param.new("tag", "", "json"),
  ]),
  Endpoint.new("/listings", "POST", [
    Param.new("page", "1", "json"),
    Param.new("query", "", "json"),
  ]),
  Endpoint.new("/loops", "POST", [
    Param.new("pool_size", "", "json"),
    Param.new("loop_note", "", "json"),
  ]),
  Endpoint.new("/login", "POST", [
    Param.new("username", "", "form"),
    Param.new("otp", "", "form"),
  ]),
  Endpoint.new("/upload", "POST", [
    Param.new("file", "", "form"),
    Param.new("caption", "", "form"),
  ]),
  Endpoint.new("/owners", "POST", [
    Param.new("owner_id", "", "json"),
  ]),
  Endpoint.new("/owners/alias", "POST", [
    Param.new("owner_id", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/python/fastapi_model_refs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
