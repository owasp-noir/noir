require "../../func_spec.cr"

# WebForms is file-path routed and every page answers both verbs, since
# the framework posts back to the page's own URL. `.ascx` and `.master`
# are param sources but never routes, so their reads are attributed to
# the pages that compose them.
expected_endpoints = [
  # Code-behind resolved through `CodeFile="default.aspx.vb"` even though
  # the file on disk is `Default.aspx.vb`; `q`/`pageNo` come from the
  # registered user control and `menuwidth` from the master page.
  # `legacy` is commented out, `prefix-` is a runtime-built key and
  # `__EVENTTARGET` is postback plumbing, so none may appear.
  Endpoint.new("/Default.aspx", "GET", [
    Param.new("CategoryID", "", "query"),
    Param.new("mode", "", "query"),
    Param.new("q", "", "query"),
    Param.new("menuwidth", "", "cookie"),
  ]),
  Endpoint.new("/Default.aspx", "POST", [
    Param.new("mode", "", "form"),
    Param.new("pageNo", "", "form"),
    Param.new("menuwidth", "", "cookie"),
  ]),

  # `Default.aspx` is the IIS default document, so it also answers the
  # bare directory URL.
  Endpoint.new("/", "GET", [
    Param.new("CategoryID", "", "query"),
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/", "POST", [
    Param.new("pageNo", "", "form"),
  ]),

  # Generic handler, read through an aliased receiver
  # (`Dim req As HttpRequest = context.Request`).
  Endpoint.new("/Image.ashx", "GET", [
    Param.new("strFullPath", "", "query"),
    Param.new("intSize", "", "query"),
  ]),
  Endpoint.new("/Image.ashx", "POST"),

  # `<WebMethod()>` maps to POST /Service.asmx/Method. The directive
  # carries only `Class=`, so the implementation is found in App_Code
  # under an unrelated filename.
  Endpoint.new("/QuoteService.asmx/GetQuote", "POST", [
    Param.new("symbol", "", "form"),
    Param.new("count", "", "form"),
  ]),
  Endpoint.new("/QuoteService.asmx/Ping", "POST"),
]

FunctionalTester.new("fixtures/aspnet/webforms/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
