require "../../../spec_helper"
require "../../../../src/tagger/framework_taggers/ruby/ruby_access"

private def shown(cnf : Access::CNF) : Array(Array(String))
  cnf.map(&.map { |atom| atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s }.sort!)
end

describe RubyAccess do
  describe ".library_callback" do
    {
      "authenticate_user!"           => [["authenticated"]],
      "authenticate_admin!"          => [["authenticated"], ["unresolved:authenticate_admin!"]],
      "authenticate_resource_owner!" => [["authenticated"], ["unresolved:authenticate_resource_owner!"]],
      "doorkeeper_authorize!"        => [["authenticated"], ["unresolved:doorkeeper_authorize!"]],
      "require_login"                => [["authenticated"], ["unresolved:require_login"]],
    }.each do |name, expected|
      it "reads #{name}" do
        shown(RubyAccess.library_callback(name)).should eq(expected)
      end
    end
  end

  describe ".role_check" do
    {
      {"current_user && current_user.has_role?(:admin)", false} => [["authenticated"], ["role:admin"]],
      {"current_user.has_role? :editor", false}                 => [["role:editor"]],
      {"current_user.has_role?('editor')", false}               => [["role:editor"]],
      {"!current_user.has_role?(:admin)", true}                 => [["role:admin"]],
      {"current_user && current_user.admin?", false}            => [["authenticated"], ["unresolved:current_user.admin?"]],
      {"current_user.role == 'admin'", false}                   => [["unresolved:current_user.role == 'admin'"]],
      {"current_user.has_role?(:admin, @org)", false}           => [["unresolved:current_user.has_role?(:admin, @org)"]],
      {"current_user.has_role?(ROLE)", false}                   => [["unresolved:current_user.has_role?(ROLE)"]],
      {"@user && @user.has_role?(:admin)", false}               => [["unresolved:@user"], ["unresolved:@user.has_role?(:admin)"]],
      {"admin? || current_user.has_role?(:admin)", false}       => [["unresolved:admin? || current_user.has_role?(:admin)"]],
      {"current_user.has_role?(:admin)", true}                  => [["unresolved:current_user.has_role?(:admin)"]],
    }.each do |(condition, when_true), expected|
      it "reads #{when_true ? "if" : "unless"} #{condition}" do
        shown(RubyAccess.role_check(condition, when_true)).should eq(expected)
      end
    end
  end

  describe ".cancan_authorize" do
    {
      "authorize! :read, Post"           => [["permission:read:Post"]],
      "authorize!(:update, Admin::Post)" => [["permission:update:Admin::Post"]],
      "authorize! :read, @post"          => [["unresolved:authorize! :read, @post"]],
      "authorize! action_name.to_sym, X" => [["unresolved:authorize! action_name.to_sym, X"]],
      "authorize! \"read\", Post"        => [["unresolved:authorize! \"read\", Post"]],
      "x || authorize!(:read, Post)"     => [["unresolved:x || authorize!(:read, Post)"]],
    }.each do |call, expected|
      it "reads #{call}" do
        shown(RubyAccess.cancan_authorize(call, guest_refused: true)).should eq(expected)
      end
    end

    it "keeps a guest's grant unresolved beside the permission" do
      shown(RubyAccess.cancan_authorize("authorize! :read, Post", guest_refused: false))
        .should eq([["permission:read:Post", "unresolved:whether the ability grants :read on Post to a guest"]])
    end
  end

  describe ".devise_route" do
    {
      {"authenticate", "authenticate do"}                                  => [["authenticated"]],
      {"authenticate", "authenticate :user do"}                            => [["authenticated"]],
      {"authenticate", "authenticate(:user) do"}                           => [["authenticated"]],
      {"authenticate", "authenticate :admin do"}                           => [["authenticated"], ["unresolved:authenticate :admin"]],
      {"authenticate", "authenticate :user, lambda { |u| u.admin? } do"}   => [["authenticated"], ["unresolved:authenticate :user, lambda { |u| u.admin? }"]],
      {"authenticated", "authenticated :user do"}                          => [["authenticated"], ["unresolved:authenticated (a routing constraint: other callers fall through to the next matching route)"]],
      {"authenticated", "authenticated :admin, ->(u) { u.super? } do |x|"} => [["authenticated"], ["unresolved:authenticated :admin, ->(u) { u.super? }"], ["unresolved:authenticated (a routing constraint: other callers fall through to the next matching route)"]],
    }.each do |(helper, line), expected|
      it "reads #{line}" do
        shown(RubyAccess.devise_route(helper, line)).should eq(expected)
      end
    end
  end

  it "lifts every clause by a condition" do
    shown(RubyAccess.lifted([[Access::Atom.new(:authenticated)], [Access::Atom.new(:role, "admin")]], "if: -> { preview? }"))
      .should eq([["authenticated", "unresolved:if: -> { preview? }"], ["role:admin", "unresolved:if: -> { preview? }"]])
  end
end
