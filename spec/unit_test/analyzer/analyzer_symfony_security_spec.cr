require "../../spec_helper"
require "../../../src/analyzer/analyzers/php/symfony_security"

describe Analyzer::Php::SymfonySecurity do
  note = Analyzer::Php::SymfonySecurity::VOTER_NOTE

  it "guards an allow_if made only of check calls joined by and" do
    guard = ->(expression : String) { Analyzer::Php::SymfonySecurity.allow_if_guard(expression) }
    guard.call("is_authenticated()").should eq("allow_if: is_authenticated()")
    guard.call("is_granted('ROLE_ADMIN') && is_fully_authenticated()").should eq("allow_if: is_granted('ROLE_ADMIN') && is_fully_authenticated()")
    guard.call(%q(is_granted("@api.access_api") and is_authenticated())).should eq(%q(allow_if: is_granted("@api.access_api") and is_authenticated()) + note)
  end

  it "leaves an allow_if that can pass anonymously undecided" do
    [
      "is_granted('ROLE_ADMIN') == false",
      "false === is_authenticated()",
      "is_authenticated() xor true",
      "is_granted('X') in [false]",
      "is_granted('ROLE_ADMIN') < 1",
      "request.query.get('q') == 'is_authenticated()'",
      %q(is_authenticated() or request.query.get("k") == "x"),
      "is_authenticated() || true",
      "not is_authenticated()",
      "!is_authenticated()",
      "is_authenticated() ? true : true",
      "true and is_authenticated()",
      "is_granted('PUBLIC_ACCESS')",
      "is_granted('IS_AUTHENTICATED_ANONYMOUSLY') and is_authenticated()",
      "is_granted('EDIT', subject)",
      "",
    ].each do |expression|
      Analyzer::Php::SymfonySecurity.allow_if_guard(expression).should be_nil
    end
  end

  it "notes a voter-decided attribute" do
    Analyzer::Php::SymfonySecurity.voter_note("@parts.read").should eq(note)
    Analyzer::Php::SymfonySecurity.voter_note("EDIT").should eq(note)
    Analyzer::Php::SymfonySecurity.voter_note("ROLE_USER").should eq("")
    Analyzer::Php::SymfonySecurity.voter_note("IS_AUTHENTICATED").should eq("")
    Analyzer::Php::SymfonySecurity.voter_note("IS_AUTHENTICATED_FULLY").should eq("")
  end
end
