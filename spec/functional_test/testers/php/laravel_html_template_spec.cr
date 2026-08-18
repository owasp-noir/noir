require "../../func_spec.cr"

# Laravel routes declared in a template-style `.php` file — HTML with islands
# of code in it.
#
# Exercises the `<?php … ?>` mode machine in the shared `Noir::PhpLexer`:
#   * The markup above the first open tag contains apostrophes ("Today's
#     report"), a `#`, a `//`, an unclosed `/*` and a `<<<EOT`. Lexed as code,
#     the first apostrophe opened a string literal that masked everything to
#     EOF, so every route in the file was lost (false-negative recovery).
#   * `?>` returns to HTML mode and `<?php` / `<?=` come back to code, so the
#     routes in the second block are found too.
#   * A route-shaped line sitting in the markup (`/html-fake`) is output text,
#     not a registration, and must not surface (false-positive suppression).
#     Neither must the `route(...)` URL helper inside the `<?=` echo tag.
expected_endpoints = [
  Endpoint.new("/from-first-block", "GET"),
  Endpoint.new("/after-html", "POST"),
  Endpoint.new("/admin/widgets", "GET"),
]

tester = FunctionalTester.new("fixtures/php/laravel_html_template/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

# Blanking the HTML has to preserve its newlines: analyzers report `code_path`
# lines from these offsets, so collapsing a 20-line header would slide every
# reported line in the file.
it "reports source lines below a 20-line HTML header unshifted" do
  endpoints = tester.app.endpoints
  endpoints.find! { |e| e.url == "/from-first-block" }.details.code_paths.first.line.should eq(25)
  endpoints.find! { |e| e.url == "/after-html" }.details.code_paths.first.line.should eq(33)
  endpoints.find! { |e| e.url == "/admin/widgets" }.details.code_paths.first.line.should eq(36)
end
