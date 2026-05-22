require "../../func_spec.cr"

ws_endpoint = Endpoint.new("/api/ws/{roomId}", "GET", [
  Param.new("roomId", "", "path"),
  Param.new("token", "", "query"),
])
ws_endpoint.protocol = "ws"

expected_endpoints = [
  Endpoint.new("/hello", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "User", "json"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("body", "User", "json"),
    Param.new("X-Trace", "", "header"),
  ]),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/v1/health", "GET"),
  Endpoint.new("/api/v1/submit", "POST", [
    Param.new("body", "Submission", "json"),
    Param.new("X-Token", "", "header"),
  ]),
  Endpoint.new("/api/v1/items/{itemId}", "GET", [
    Param.new("itemId", "", "path"),
    Param.new("category", "", "query"),
  ]),
  Endpoint.new("/sessions/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/profile", "PATCH", [
    Param.new("email", "", "form"),
    Param.new("phone", "", "form"),
  ]),
  Endpoint.new("/uploads/{uploadId}", "POST", [
    Param.new("verbose", "", "query"),
    Param.new("files", "", "form"),
    Param.new("tags", "", "form"),
    Param.new("X-Batch", "", "header"),
  ]),
  Endpoint.new("/raw", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/search", "QUERY", [
    Param.new("scope", "", "query"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/stream/{streamId}", "GET", [
    Param.new("streamId", "", "path"),
  ]),
  Endpoint.new("/advanced-search/{searchId}", "QUERY", [
    Param.new("searchId", "", "path"),
    Param.new("cursor", "", "query"),
  ]),
  Endpoint.new("/api/reports/{reportId}", "GET", [
    Param.new("reportId", "", "path"),
    Param.new("X-Report-Trace", "", "header"),
  ]),
  Endpoint.new("/api/projects", "GET"),
  Endpoint.new("/api/projects", "POST"),
  Endpoint.new("/api/projects/{projectId}", "GET", [
    Param.new("projectId", "", "path"),
  ]),
  Endpoint.new("/api/projects/{projectId}", "PATCH", [
    Param.new("projectId", "", "path"),
  ]),
  Endpoint.new("/api/projects/{projectId}", "DELETE", [
    Param.new("projectId", "", "path"),
  ]),
  Endpoint.new("/api/admin/audit/{auditId}", "GET", [
    Param.new("auditId", "", "path"),
    Param.new("expand", "", "query"),
  ]),
  Endpoint.new("/imports/{importId}", "POST", [
    Param.new("importId", "", "path"),
    Param.new("body", "ImportRequest", "json"),
  ]),
  Endpoint.new("/webhooks/{webhookId}", "POST", [
    Param.new("webhookId", "", "path"),
    Param.new("dryRun", "", "query"),
    Param.new("X-Signature", "", "header"),
    Param.new("body", "WebhookPayload", "json"),
  ]),
  Endpoint.new("/**", "GET"),
  Endpoint.new("/api/assets/**", "GET"),
  Endpoint.new("/webjars/**", "GET"),
  Endpoint.new("/portal/context/status", "GET"),
  Endpoint.new("/api/teams/{teamId}", "GET", [
    Param.new("teamId", "", "path"),
    Param.new("filter", "", "query"),
  ]),
  Endpoint.new("/api/teams/{teamId}", "PUT", [
    Param.new("teamId", "", "path"),
    Param.new("body", "Team", "json"),
  ]),
  Endpoint.new("/api/teams/{teamId}", "DELETE", [
    Param.new("teamId", "", "path"),
  ]),
  Endpoint.new("/api/tasks", "GET"),
  Endpoint.new("/api/tasks", "POST"),
  Endpoint.new("/api/tasks/{taskId}", "GET", [
    Param.new("taskId", "", "path"),
  ]),
  Endpoint.new("/api/tasks/{taskId}", "PATCH", [
    Param.new("taskId", "", "path"),
  ]),
  Endpoint.new("/api/tasks/{taskId}", "DELETE", [
    Param.new("taskId", "", "path"),
  ]),
  ws_endpoint,
]

FunctionalTester.new("fixtures/java/javalin/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
