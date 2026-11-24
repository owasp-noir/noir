require "../../../spec_helper"
require "../../../../src/tagger/framework_taggers/python/python_auth_access"

# Atoms as text, with an unresolved atom's fragment shown.
private def shown(cnf : Access::CNF) : Array(Array(String))
  cnf.map(&.map { |atom| atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s }.sort!)
end

private def library(qualified : String, text : String, method : String = "GET", login_disabled : Bool = false) : Array(Array(String))?
  _, args, source = DjangoAccess.call(text).not_nil!
  PythonAuthAccess.library_decorator(qualified, args, source, method, login_disabled).try { |cnf| shown(cnf) }
end

describe PythonAuthAccess do
  describe ".library_decorator" do
    {
      {"flask_login.login_required", "@login_required"}                           => [["authenticated"]],
      {"flask_security.login_required", "@login_required"}                        => [["authenticated"]],
      {"flask_security.decorators.roles_accepted", "@roles_accepted('a')"}        => [["role:a"]],
      {"flask_jwt_extended.jwt_required", "@jwt_required()"}                      => [["authenticated"]],
      {"flask_jwt_extended.jwt_required", "@jwt_required(locations=['headers'])"} => [["authenticated"]],
      {"flask_jwt_extended.jwt_required", "@jwt_required(optional=False)"}        => [["authenticated"]],
      {"flask_jwt_extended.jwt_required", "@jwt_required(optional=True)"}         => [["unresolved:jwt_required(optional=True)"]],
      {"flask_jwt_extended.jwt_required", "@jwt_required(True)"}                  => [["unresolved:jwt_required(True)"]],
      {"flask_jwt_extended.jwt_required", "@jwt_required(optional=OPTIONAL)"}     => [["unresolved:jwt_required(optional=OPTIONAL)"]],
      {"flask_jwt_extended.jwt_required", "@jwt_required(fresh=True)"}            => [["authenticated"], ["unresolved:jwt_required(fresh=True)"]],
      {"flask_jwt_extended.jwt_required", "@jwt_required(refresh=True)"}          => [["authenticated"], ["unresolved:jwt_required(refresh=True)"]],
      {"flask_jwt_extended.jwt_required", "@jwt_required(**opts)"}                => [["unresolved:jwt_required(**opts)"]],
      {"flask_jwt_extended.jwt_required", "@jwt_required"}                        => [["authenticated"], ["unresolved:jwt_required (flask-jwt-extended 4 needs jwt_required())"]],
      {"flask_jwt_extended.jwt_optional", "@jwt_optional()"}                      => [["unresolved:jwt_optional()"]],
      {"flask_jwt_extended.fresh_jwt_required", "@fresh_jwt_required()"}          => [["authenticated"], ["unresolved:fresh_jwt_required()"]],
      {"flask_security.auth_required", "@auth_required()"}                        => [["authenticated"]],
      {"flask_security.auth_required", "@auth_required('token', 'session')"}      => [["authenticated"]],
      {"flask_security.auth_required", "@auth_required('session', within=5)"}     => [["authenticated"], ["unresolved:auth_required('session', within=5)"]],
      {"flask_security.http_auth_required", "@http_auth_required('realm')"}       => [["authenticated"]],
      {"flask_security.roles_required", "@roles_required('admin', 'editor')"}     => [["role:admin"], ["role:editor"]],
      {"flask_security.roles_required", "@roles_required('admin', EDITOR)"}       => [["role:admin"], ["unresolved:EDITOR"]],
      {"flask_security.roles_accepted", "@roles_accepted('admin', 'editor')"}     => [["role:admin", "role:editor"]],
      {"flask_security.roles_accepted", "@roles_accepted(*ROLES)"}                => [["unresolved:roles_accepted(*ROLES)"]],
      {"flask_security.roles_required", "@roles_required()"}                      => [["unresolved:roles_required()"]],
      {"sanic_jwt.protected", "@protected()"}                                     => [["authenticated"]],
    }.each do |(qualified, text), expected|
      it "reads #{qualified} as #{text}" do
        library(qualified, text).should eq(expected)
      end
    end

    it "keeps a flask_login guard liftable where the project sets LOGIN_DISABLED" do
      library("flask_login.login_required", "@login_required", login_disabled: true).should eq([["authenticated", "unresolved:LOGIN_DISABLED"]])
    end

    it "reads nothing exact for an OPTIONS request the library lets through" do
      library("flask_login.login_required", "@login_required", "OPTIONS").should eq([["unresolved:login_required (skipped for OPTIONS)"]])
      library("flask_security.roles_required", "@roles_required('admin')", "OPTIONS").should eq([["role:admin"]])
    end

    it "says nothing about a name it does not know" do
      library("flask_security.permission_required", "@permission_required('x')").should be_nil
      library("acme.login_required", "@login_required").should be_nil
    end
  end

  describe ".httpauth" do
    {
      {"@auth.login_required", true}                                     => [["authenticated"]],
      {"@auth.login_required(role='admin')", true}                       => [["role:admin"]],
      {"@auth.login_required(role=['admin', 'moderator'])", true}        => [["role:admin", "role:moderator"]],
      {"@auth.login_required(role=['admin', ['user', 'editor']])", true} => [["role:admin", "role:user"], ["role:admin", "role:editor"]],
      {"@auth.login_required(role=ROLE)", true}                          => [["unresolved:ROLE"]],
      {"@auth.login_required(role='admin')", false}                      => [["authenticated"], ["unresolved:auth.login_required(role='admin')"]],
      {"@auth.login_required(optional=True)", true}                      => [["unresolved:auth.login_required(optional=True)"]],
      {"@authenticate(token_auth, role='admin')", true}                  => [["role:admin"]],
    }.each do |(text, bound), expected|
      it "reads #{text}#{bound ? "" : " on an object not known to be Flask-HTTPAuth's"}" do
        _, args, source = DjangoAccess.call(text).not_nil!
        shown(PythonAuthAccess.httpauth(args, source, bound)).should eq(expected)
      end
    end
  end

  describe ".scoped" do
    {
      "@scoped('admin')"                       => [["authenticated"], ["scope:admin"]],
      "@scoped(['a', 'b'])"                    => [["authenticated"], ["scope:a"], ["scope:b"]],
      "@scoped(['a', 'b'], require_all=False)" => [["authenticated"], ["scope:a", "scope:b"]],
      "@scoped(['a', 'b'], False)"             => [["authenticated"], ["scope:a", "scope:b"]],
      "@scoped('user:read')"                   => [["authenticated"], ["scope:user:read", "unresolved:scoped('user:read') (a broader scope also passes)"]],
      "@scoped(SCOPES)"                        => [["authenticated"], ["unresolved:SCOPES"]],
      "@scoped(None)"                          => [["unresolved:scoped(None)"]],
      "@scoped(['a'], require_all=ALL)"        => [["authenticated"], ["unresolved:scoped(['a'], require_all=ALL)"]],
    }.each do |text, expected|
      it "reads #{text}" do
        _, args, source = DjangoAccess.call(text).not_nil!
        shown(PythonAuthAccess.scoped(args, source, false)).should eq(expected)
      end
    end

    it "keeps the scopes unresolved where the project replaces the check" do
      shown(PythonAuthAccess.scoped("'admin'", "scoped('admin')", true)).should eq([["authenticated"], ["unresolved:scoped('admin')"]])
    end
  end

  it "keeps a Flask-AppBuilder permission open to the Public role setting" do
    shown(PythonAuthAccess.fab("can_list on V", "has_access")).should eq([["authenticated", "unresolved:has_access"], ["unresolved:can_list on V", "unresolved:has_access"]])
  end

  it "binds the names a from-import brings in" do
    source = <<-PY
      from flask_security.decorators import roles_required as needs
      from flask_login import (
          login_required,  # comment
          current_user,
      )
      from .local import thing
      PY
    PythonAuthAccess.from_imports(source).should eq({
      "needs"          => "flask_security.decorators.roles_required",
      "login_required" => "flask_login.login_required",
      "current_user"   => "flask_login.current_user",
      "thing"          => ".local.thing",
    })
  end
end
