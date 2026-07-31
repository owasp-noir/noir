require "../../func_spec.cr"

# WebForms is file-path routed. A page answers POST when something proves
# it can — a server-side form (its own or its master's), a read from the
# form collection, or explicit postback handling — and GET only otherwise.
# `.ascx` and `.master` are param sources but never routes, so their reads
# are attributed to the pages that compose them.
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

  # Its own `<form runat="server">` makes the page a POST target even
  # though nothing reads the form collection.
  Endpoint.new("/Contact.aspx", "GET", [
    Param.new("topic", "", "query"),
  ]),
  Endpoint.new("/Contact.aspx", "POST"),

  # Generic handler, read through an aliased receiver
  # (`Dim req As HttpRequest = context.Request`). It reads only the query
  # string and has no form, so it is not claimed as a POST target.
  Endpoint.new("/Image.ashx", "GET", [
    Param.new("strFullPath", "", "query"),
    Param.new("intSize", "", "query"),
  ]),

  # `<WebMethod()>` maps to POST /Service.asmx/Method. The directive
  # carries only `Class=`, so the implementation is found in App_Code
  # under an unrelated filename.
  Endpoint.new("/QuoteService.asmx/GetQuote", "POST", [
    Param.new("symbol", "", "form"),
    Param.new("count", "", "form"),
  ]),
  Endpoint.new("/QuoteService.asmx/Ping", "POST"),
  # No form, no master and no postback handling: GET only.
  Endpoint.new("/BugTest.aspx", "GET", [
    Param.new("RealParam", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/aspnet/webforms/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
