require "../../../spec_helper"
require "../../../../src/miniparsers/ts_decorator_extractor"
require "../../../../src/tagger/framework_taggers/javascript/nestjs_access"

# Reads the decorator on a method of a one-class source that starts with
# `prelude`, and returns its requirement with each unresolved atom's text.
private def read_metadata(decorator : String, prelude : String = "") : Array(Array(String))?
  source = "#{prelude}\nclass C {\n  #{decorator}\n  m() {}\n}\n"
  parsed = Noir::TsDecoratorExtractor.extract(source, "c.ts").first.methods.first.decorators.first
  NestjsAccess.metadata(parsed.name, parsed.args, parsed.text, source).try do |_, cnf|
    cnf.map(&.map { |atom| atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s }.sort!)
  end
end

describe NestjsAccess do
  {
    "@Roles('admin')"                                      => [["role:admin"]],
    "@Roles('admin', \"editor\")"                          => [["role:admin", "role:editor"]],
    "@Roles(['admin', 'editor'])"                          => [["role:admin", "role:editor"]],
    "@Roles(`admin`)"                                      => [["role:admin"]],
    "@Roles(`${prefix}admin`)"                             => [["unresolved:`${prefix}admin`"]],
    "@Roles('admin', Role.Admin)"                          => [["role:admin", "unresolved:Role.Admin"]],
    "@Roles(...ADMINS)"                                    => [["unresolved:...ADMINS"]],
    "@Roles(roleFor('x'))"                                 => [["unresolved:roleFor('x')"]],
    "@Roles()"                                             => [["unresolved:@Roles()"]],
    "@Permissions('posts:write')"                          => [["permission:posts:write"]],
    "@RequirePermissions('a', 'b')"                        => [["permission:a", "permission:b"], ["unresolved:@RequirePermissions('a', 'b')"]],
    "@Scopes('read')"                                      => [["scope:read"]],
    "@Scopes('read', 'write')"                             => [["scope:read", "scope:write"], ["unresolved:@Scopes('read', 'write')"]],
    "@CheckPolicies(new ReadPolicy())"                     => [["unresolved:@CheckPolicies(new ReadPolicy())"]],
    "@CheckAbilities({ action: 'read', subject: 'Post' })" => [["unresolved:@CheckAbilities({ action: 'read', subject: 'Post' })"]],
    "@SetMetadata('roles', ['admin'])"                     => [["role:admin"]],
    "@SetMetadata('roles', ROLES)"                         => [["unresolved:ROLES"]],
    "@SetMetadata('roles')"                                => [["unresolved:@SetMetadata('roles')"]],
  }.each do |decorator, expected|
    it "reads #{decorator}" do
      read_metadata(decorator).should eq(expected)
    end
  end

  it "reads no metadata off other decorators" do
    read_metadata("@SetMetadata('isPublic', true)").should be_nil
    read_metadata("@UseGuards(RolesGuard)").should be_nil
    read_metadata("@Throttle({ default: { limit: 3 } })").should be_nil
  end

  it "resolves a string constant or enum member declared in the same file" do
    prelude = <<-TS
      export enum Role { User = 'user', Admin = "admin" }
      enum Level { Low, High }
      export const Perm = { Write: 'posts:write' } as const;
      const EDITOR = 'editor';
      function f() {
        const LOCAL = 'local';
      }
      TS
    read_metadata("@Roles(Role.Admin, EDITOR)", prelude).should eq([["role:admin", "role:editor"]])
    read_metadata("@Permissions(Perm.Write)", prelude).should eq([["permission:posts:write"]])
    read_metadata("@Roles(Level.High, LOCAL, Role.Owner, Other.Admin)", prelude).should eq([["unresolved:LOCAL", "unresolved:Level.High", "unresolved:Other.Admin", "unresolved:Role.Owner"]])
  end
end
