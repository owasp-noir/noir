require "../../spec_helper"
require "../../../src/analyzer/engines/php_engine"

class PhpEngineSpecHarness < Analyzer::Php::PhpEngine
  def analyze_file(path : String) : Array(Endpoint)
    [] of Endpoint
  end

  def method_body_after(content : String, start_pos : Int32) : Tuple(String, Int32)?
    extract_php_method_body_after(content, start_pos)
  end
end

describe Analyzer::Php::PhpEngine do
  it "extracts method bodies without treating strings or comments as braces" do
    content = <<-PHP
      <?php
      class DemoController {
          #[Route('/demo')]
          public function show(): JsonResponse
          {
              $literal = "{";
              /* } */
              if ($literal) {
                  return $this->json($literal);
              }
          }
      }
      PHP

    route_start = content.index("#[Route")
    route_start.should_not be_nil

    method_body = route_start ? PhpEngineSpecHarness.new(create_test_options).method_body_after(content, route_start) : nil
    method_body.should_not be_nil
    if method_body
      body, start_line = method_body
      start_line.should eq(5)
      body.should contain("$this->json")
      body.should_not contain("class DemoController")
    end
  end
end
