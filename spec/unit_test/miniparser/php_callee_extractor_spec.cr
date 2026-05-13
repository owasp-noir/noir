require "../../spec_helper"
require "../../../src/miniparsers/php_callee_extractor"

describe Noir::PhpCalleeExtractor do
  it "extracts object, static, and bare calls with line numbers" do
    body = <<-PHP
      $users = UserService::list($request->getQueryParams()['page']);
      AuditLog::write('list');
      $response->getBody()->write(json_encode($users));
      PHP

    callees = Noir::PhpCalleeExtractor.callees_for_body(body, "index.php", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"$request->getQueryParams", 10},
      {"UserService::list", 10},
      {"AuditLog::write", 11},
      {"$response->getBody()->write", 12},
      {"json_encode", 12},
    ])
  end

  it "skips comments and PHP language constructs" do
    body = <<-PHP
      // AuditLog::write('ignored');
      if (isset($payload['name'])) {
        return JsonResponder::created($response, $payload);
      }
      PHP

    callees = Noir::PhpCalleeExtractor.callees_for_body(body, "index.php", 20)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"JsonResponder::created", 22},
    ])
  end

  it "skips strings and block comments while preserving qualified function calls" do
    body = <<-'PHP'
      $message = "AuditLog::write('ignored')";
      /*
        UserService::delete($payload);
      */
      $value = App\Support\sanitize($request->getParsedBody());
      \Vendor\Package\notify($value);
      PHP

    callees = Noir::PhpCalleeExtractor.callees_for_body(body, "index.php", 30)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"$request->getParsedBody", 34},
      {"App\\Support\\sanitize", 34},
      {"\\Vendor\\Package\\notify", 35},
    ])
  end
end
