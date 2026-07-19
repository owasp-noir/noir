require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# Symfony Console (setName + addArgument/addOption, getenv). The fixture also
# trips php_pure (any <?php) and php_symfony (Symfony\ namespace), so 3 techs.
endpoints = [
  build.call("cli://cli_symfony", [
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://cli_symfony/app:create-user", [
    Param.new("username", "", "argument"),
    Param.new("admin", "", "flag"),
  ]),
  # php_pure's per-file GET pseudo-endpoint, same as cli_robo_fp below.
  # This directory has no composer.json, so php_pure reads it as a plain-PHP
  # tree where the directory itself is the document root (#2358).
  Endpoint.new("/src/CreateUserCommand.php", "GET"),
]

FunctionalTester.new("fixtures/php/cli_symfony/", {
  :techs     => 3,
  :endpoints => endpoints.size,
}, endpoints).perform_tests

# Robo (`@command` docblock tag) regression: the tag must bind ONLY to the
# very next method signature, never stay sticky for the rest of the file.
# fixtures/php/cli_robo_fp/RoboFile.php has a constructor BEFORE the first
# `@command` tag and an untagged helper method (formatOutput) AFTER the
# tagged command (fooBar) — neither may contribute params to any endpoint.
robo_endpoints = [
  build.call("cli://cli_robo_fp/foo:bar", [
    Param.new("arg", "", "argument"),
  ]),
  # php_pure's generic per-file GET pseudo-endpoint (no framework marker
  # is present here to suppress it, unlike the Laravel/Symfony fixtures).
  Endpoint.new("/RoboFile.php", "GET"),
]

robo_tester = FunctionalTester.new("fixtures/php/cli_robo_fp/", {
  :techs     => 2,
  :endpoints => robo_endpoints.size,
}, robo_endpoints)
robo_tester.perform_tests

it "does not attach the constructor's or the untagged helper's params to the Robo command" do
  ep = robo_tester.app.endpoints.find { |e| e.url == "cli://cli_robo_fp/foo:bar" }
  ep.should_not be_nil
  ep.try(&.params.map(&.name)).should eq(["arg"])
  # No root `cli://cli_robo_fp` endpoint should exist (the constructor,
  # which runs before any `@command` tag, must not fall back to it).
  robo_tester.app.endpoints.any? { |e| e.url == "cli://cli_robo_fp" }.should be_false
end

# WP-CLI regression: `$args`/`$assoc_args` reads must be scoped to the
# specific method whose OWN signature is the conventional
# `($args, $assoc_args)` callback, never the whole class body.
# fixtures/php/cli_wp_cli_fp/command.php has an unrelated private helper
# (build_report) that also uses a local variable named `$args` — its
# `$args[7]` read must not leak into the registered command's params.
wp_cli_endpoints = [
  build.call("cli://cli_wp_cli_fp/foo bar", [
    Param.new("arg0", "", "argument"),
    Param.new("format", "", "flag"),
  ]),
  # php_pure's generic per-file GET pseudo-endpoint (no framework marker
  # is present here to suppress it, unlike the Laravel/Symfony fixtures).
  Endpoint.new("/command.php", "GET"),
]

wp_cli_tester = FunctionalTester.new("fixtures/php/cli_wp_cli_fp/", {
  :techs     => 2,
  :endpoints => wp_cli_endpoints.size,
}, wp_cli_endpoints)
wp_cli_tester.perform_tests

it "does not leak the unrelated helper's $args[7] into the WP-CLI command's params" do
  ep = wp_cli_tester.app.endpoints.find { |e| e.url == "cli://cli_wp_cli_fp/foo bar" }
  ep.should_not be_nil
  ep.try(&.params.map(&.name).sort!).should eq(["arg0", "format"])
end

# Laravel Artisan regression: the idiomatic `{arg : description}` /
# `{--flag : description}` signature syntax must yield clean param names,
# not the whole " : description" suffix baked into the name.
# fixtures/php/cli_artisan_fp/SendMail.php never calls
# $this->argument()/$this->option() by literal name, so the described
# `$signature` tokens are the ONLY source of these params.
artisan_endpoints = [
  build.call("cli://cli_artisan_fp/mail:send", [
    Param.new("user", "", "argument"),
    Param.new("queue", "", "flag"),
  ]),
  # See the cli_symfony note: no composer.json here either, so php_pure
  # emits its per-file pseudo-endpoint.
  Endpoint.new("/SendMail.php", "GET"),
]

artisan_tester = FunctionalTester.new("fixtures/php/cli_artisan_fp/", {
  :techs     => 3,
  :endpoints => artisan_endpoints.size,
}, artisan_endpoints)
artisan_tester.perform_tests

it "strips the ' : description' suffix from described Artisan signature tokens" do
  ep = artisan_tester.app.endpoints.find { |e| e.url == "cli://cli_artisan_fp/mail:send" }
  ep.should_not be_nil
  names = ep.try(&.params.map(&.name)).not_nil!
  names.should eq(["user", "queue"])
  names.each do |name|
    name.should_not contain(" ")
    name.should_not contain(":")
  end
end
