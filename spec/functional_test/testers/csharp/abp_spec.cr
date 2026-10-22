require "../../func_spec.cr"

paged = [
  Param.new("Sorting", "", "query"),
  Param.new("SkipCount", "", "query"),
  Param.new("MaxResultCount", "", "query"),
]

expected_endpoints = [
  # BookAppService: hand-written conventional methods (issue #2915).
  Endpoint.new("/api/app/book/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/app/book", "GET", [Param.new("Filter", "", "query")] + paged),
  Endpoint.new("/api/app/book", "POST", [
    Param.new("Name", "", "json"),
    Param.new("Price", "", "json"),
  ]),
  Endpoint.new("/api/app/book/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/app/book/{id}/publish", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/api/app/book/author-lookup/{authorId}", "GET", [
    Param.new("authorId", "", "path"),
    Param.new("filter", "", "query"),
  ]),
  Endpoint.new("/api/books/{id}/price", "PUT", [
    Param.new("id", "", "path"),
    Param.new("price", "", "query"),
  ]),

  # AuthorAppService: CrudAppService's inherited actions, DELETE hidden.
  Endpoint.new("/api/app/author/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/app/author", "GET", paged),
  Endpoint.new("/api/app/author", "POST", [
    Param.new("Name", "", "json"),
    Param.new("BirthDate", "", "json"),
  ]),
  Endpoint.new("/api/app/author/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("Name", "", "json"),
    Param.new("BirthDate", "", "json"),
  ]),
  Endpoint.new("/api/app/author/stats", "GET"),

  # A second assembly registered with `RootPath = "reporting"`.
  Endpoint.new("/api/reporting/sales-report/summary", "GET", [Param.new("year", "", "query")]),
  Endpoint.new("/api/reporting/sales-report/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("title", "", "query"),
  ]),
  Endpoint.new("/api/reporting/sales-report/totals", "GET"),
  Endpoint.new("/api/reports/ping", "GET"),
  Endpoint.new("/api/reporting/sales-report/export", "POST", [
    Param.new("format", "", "query"),
    Param.new("Title", "", "json"),
    Param.new("Year", "", "json"),
  ]),

  # Hand-written controller, owned by cs_aspnet_core_mvc.
  Endpoint.new("/api/ping", "GET"),
]

tester = FunctionalTester.new("fixtures/csharp/abp/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ABP conventional controllers", tags: "functional" do
  it "skips services and methods that opt out of remoting" do
    urls = tester.app.endpoints.map(&.url)
    urls.any?(&.includes?("recalculate")).should be_false
    urls.any?(&.includes?("author-sync")).should be_false
    urls.any?(&.includes?("purge")).should be_false
    urls.any?(&.includes?("export-request")).should be_false
    tester.app.endpoints.any? { |e| e.url == "/api/app/author/{id}" && e.method == "DELETE" }.should be_false
  end

  it "leaves services no ConventionalControllers.Create covers alone" do
    tester.app.endpoints.any?(&.url.includes?("identity-user")).should be_false
  end

  it "tags conventional endpoints cs_abp and does not re-emit them as MVC" do
    tester.app.endpoints.select(&.url.starts_with?("/api/app/")).each do |endpoint|
      endpoint.details.technology.should eq "cs_abp"
    end
    tester.app.endpoints.find!(&.url.==("/api/ping")).details.technology.should eq "cs_aspnet_core_mvc"
  end
end
