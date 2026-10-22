require "../../func_spec.cr"

# Wasp Spec (`main.wasp.ts` + feature `*.wasp.ts`, Wasp 0.24+). The app's
# `auth` is a config object imported from another spec file.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/login", "GET"),
  Endpoint.new("/tasks/:taskId", "GET", [Param.new("taskId", "", "path")]),
  Endpoint.new("/operations/get-tasks", "POST"),
  Endpoint.new("/operations/get-oldest-task", "POST", [Param.new("listId", "", "json")]),
  Endpoint.new("/operations/create-task", "POST", [
    Param.new("description", "", "json"),
    Param.new("isDone", "", "json"),
  ]),
  # `updateTask as renameTask`: Wasp names the operation after the local alias.
  Endpoint.new("/operations/rename-task", "POST", [
    Param.new("id", "", "json"),
    Param.new("title", "", "json"),
  ]),
  Endpoint.new("/api/tasks/export", "GET", [
    Param.new("format", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/api/tasks/:listId/upload", "POST", [
    Param.new("listId", "", "path"),
    Param.new("tasks", "", "json"),
  ]),
  Endpoint.new("/crud/tasks/get", "POST", [Param.new("id", "", "json")]),
  Endpoint.new("/crud/tasks/update", "POST", [Param.new("id", "", "json")]),
  Endpoint.new("/auth/me", "GET"),
  Endpoint.new("/auth/logout", "POST"),
  Endpoint.new("/auth/email/login", "POST", [Param.new("email", "", "json"), Param.new("password", "", "json")]),
  Endpoint.new("/auth/email/signup", "POST", [Param.new("email", "", "json"), Param.new("password", "", "json")]),
  Endpoint.new("/auth/email/request-password-reset", "POST", [Param.new("email", "", "json")]),
  Endpoint.new("/auth/email/reset-password", "POST", [Param.new("token", "", "json"), Param.new("password", "", "json")]),
  Endpoint.new("/auth/email/verify-email", "POST", [Param.new("token", "", "json")]),
  Endpoint.new("/auth/github/login", "GET"),
  Endpoint.new("/auth/github/callback", "GET", [Param.new("code", "", "query"), Param.new("state", "", "query")]),
  Endpoint.new("/auth/exchange-code", "POST", [Param.new("code", "", "json")]),
]

FunctionalTester.new("fixtures/typescript/wasp_ts/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
