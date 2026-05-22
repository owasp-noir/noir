require "../../func_spec.cr"

# Coverage for real-world NestJS patterns the analyzer used to miss:
#   - `app.setGlobalPrefix('api')` propagation
#   - `@Controller({ version: ['1', '2'] })` → `/v1` and `/v2`
#   - `@Sse()` treated as GET
#   - `@UploadedFile`/`@UploadedFiles` (named + unnamed)
#   - `@HostParam` surfacing subdomain captures
#   - commented-out decorators ignored (FP fix)
#   - `setGlobalPrefix(..., { exclude: [...] })` avoiding prefix FPs
#   - unnamed `@Query()` / `@Headers()` surfacing broad request params
expected_endpoints = [
  # /events under v1 and v2 with @Sse('stream') + bare @Sse()
  Endpoint.new("/api/v1/events/stream", "GET", [] of Param),
  Endpoint.new("/api/v2/events/stream", "GET", [] of Param),
  Endpoint.new("/api/v1/events", "GET", [] of Param),
  Endpoint.new("/api/v2/events", "GET", [] of Param),

  # Subdomain host param surfaces as a path-typed param.
  Endpoint.new("/api/tenant/:slug", "GET", [
    Param.new("slug", "", "path"),
    Param.new("account", "", "path"),
  ]),
  Endpoint.new("/api/tenant/lookup", "GET", [
    Param.new("query", "", "query"),
    Param.new("headers", "", "header"),
  ]),

  # Multipart upload routes — named file / files args.
  Endpoint.new("/api/uploads/avatar", "POST", [
    Param.new("avatar", "", "body"),
  ]),
  Endpoint.new("/api/uploads/attachments", "POST", [
    Param.new("files", "", "body"),
  ]),
  # Bare @UploadedFile() / @UploadedFiles() default to 'file' / 'files'.
  Endpoint.new("/api/uploads/blob", "POST", [
    Param.new("file", "", "body"),
  ]),
  Endpoint.new("/api/uploads/bulk", "POST", [
    Param.new("files", "", "body"),
  ]),
  # Global-prefix exclude: this POST remains unprefixed.
  Endpoint.new("/uploads/public", "POST", [
    Param.new("file", "", "body"),
  ]),
  # Global-prefix exclude: health remains unprefixed.
  Endpoint.new("/health", "GET", [] of Param),
]

FunctionalTester.new("fixtures/typescript/nestjs_advanced/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
