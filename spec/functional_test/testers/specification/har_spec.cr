require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("https://www.hahwul.com/", "GET", [
    Param.new("Host", "www.hahwul.com", "header"),
    Param.new("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:123.0) Gecko/20100101 Firefox/123.0", "header"),
    Param.new("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", "header"),
    Param.new("_ga", "GA1.1.1310623768.1671977578", "cookie"),
    Param.new("_ga_N9SYSZ280B", "GS1.1.1710602187.53.0.1710602187.0.0.0", "cookie"),
  ]),
]

instance = FunctionalTester.new("fixtures/specification/har/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints)

instance.url = "https://www.hahwul.com"
instance.perform_tests
