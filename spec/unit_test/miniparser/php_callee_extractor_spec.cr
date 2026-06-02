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

  it "preserves static property object chains" do
    body = <<-'PHP'
      $page = Yii::$app->request->get('page');
      $token = \App\Container::$request->headers->get('Authorization');
      PHP

    callees = Noir::PhpCalleeExtractor.callees_for_body(body, "index.php", 40)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"Yii::$app->request->get", 40},
      {"\\App\\Container::$request->headers->get", 41},
    ])
  end

  it "handles namespaced type hints in closure declarations" do
    body = <<-'PHP'
      $app->group('/api', static function (\Slim\Routing\RouteCollectorProxy $group) use ($app): void {
        Yii::$app->request->get('page');
      });
      PHP

    callees = Noir::PhpCalleeExtractor.callees_for_body(body, "index.php", 50)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"$app->group", 50},
      {"Yii::$app->request->get", 51},
    ])
  end

  it "skips named function declarations" do
    body = <<-PHP
      function sanitize_name($value) {
      }

      sanitize_name($payload);
      PHP

    callees = Noir::PhpCalleeExtractor.callees_for_body(body, "index.php", 60)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"sanitize_name", 63},
    ])
  end

  # `sanitize_line` scans the raw byte buffer (ASCII delimiters never collide
  # with UTF-8 multi-byte sequences). CJK comments/strings must still be
  # blanked correctly, and the half-megabyte CJK string literals in CRMEB used
  # to make the old `String#[](Int)` loop O(n^2) — here we just assert
  # correctness on multi-byte content.
  it "blanks multi-byte (CJK) comments and string literals" do
    body = <<-PHP
      // 用户管理 AuditLog::write('忽略');
      $name = '用户名称';
      UserService::create($name); // 创建用户
      PHP

    callees = Noir::PhpCalleeExtractor.callees_for_body(body, "index.php", 70)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"UserService::create", 72},
    ])
  end
end
