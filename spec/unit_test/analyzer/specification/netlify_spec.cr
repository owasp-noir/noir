require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/netlify"

private def analyze_netlify(redirects_content : String?, toml_content : String?) : Array(Endpoint)
  tmp_dir = ""
  redirects_path = ""
  toml_path = ""
  tmp_dir = File.tempname("netlify-analyzer")
  Dir.mkdir_p(tmp_dir)

  locator = CodeLocator.instance
  locator.clear "netlify-redirects"
  locator.clear "netlify-toml"

  redirects_path = File.join(tmp_dir, "_redirects")
  toml_path = File.join(tmp_dir, "netlify.toml")

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
  tmp_dir_s = tmp_dir.to_s
  redirects_path_s = redirects_path.to_s
  toml_path_s = toml_path.to_s
  if !tmp_dir_s.empty? && Dir.exists?(tmp_dir_s)
    File.delete(redirects_path_s) if File.exists?(redirects_path_s)
    File.delete(toml_path_s) if File.exists?(toml_path_s)
    Dir.delete(tmp_dir_s)
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
