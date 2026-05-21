require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/netlify"

private def analyze_netlify(redirects_content : String?, toml_content : String?) : Array(Endpoint)
  temp_dir = File.join(Dir.tempdir, "netlify-analyzer-#{Process.pid}-#{Time.utc.to_unix_ms}")
  redirects_path = File.join(temp_dir, "_redirects")
  toml_path = File.join(temp_dir, "netlify.toml")

  Dir.mkdir_p(temp_dir)

  locator = CodeLocator.instance
  locator.clear "netlify-redirects"
  locator.clear "netlify-toml"

  begin
    if redirects_content
      File.write(redirects_path, redirects_content)
      locator.push "netlify-redirects", redirects_path
    end

    if toml_content
      File.write(toml_path, toml_content)
      locator.push "netlify-toml", toml_path
    end

    options = create_test_options
    analyzer = Analyzer::Specification::Netlify.new options
    analyzer.analyze
  ensure
    File.delete(redirects_path) if File.exists?(redirects_path)
    File.delete(toml_path) if File.exists?(toml_path)
    Dir.delete(temp_dir) if Dir.exists?(temp_dir)
  end
end

describe "Netlify Analyzer" do
  it "extracts endpoint paths from _redirects lines" do
    endpoints = analyze_netlify <<-TXT, nil
      # comments are ignored
      /api/*    /.netlify/functions/api/:splat   200
      /old/*    /new/:splat                       301
      /checkout https://payments.example.com/pay  302
      invalid_line_without_target
      TXT

    endpoints.size.should eq 3
    endpoints.map(&.url).should eq ["/api/*", "/old/*", "/checkout"]
    endpoints.all? { |e| e.method == "ANY" }.should be_true
  end

  it "extracts endpoint paths from netlify.toml redirects and edge functions" do
    endpoints = analyze_netlify nil, <<-TOML
      [[redirects]]
        from = "/api/*"
        to = "/.netlify/functions/api/:splat"
        status = 200

      [[edge_functions]]
        path = "/users/*"
        function = "users"
      TOML

    endpoints.map(&.url).sort!.should eq ["/api/*", "/users/*"]
    endpoints.all? { |e| e.method == "ANY" }.should be_true
  end

  it "combines routes from both files" do
    endpoints = analyze_netlify "/old/* /new/:splat 301\n", <<-TOML
      [[redirects]]
        from = "/api/*"
        to = "/.netlify/functions/api/:splat"
      TOML

    endpoints.map(&.url).sort!.should eq ["/api/*", "/old/*"]
  end
end
