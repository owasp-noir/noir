require "../../../spec_helper"
require "../../../../src/miniparsers/ts_decorator_extractor"
require "../../../../src/tagger/framework_taggers/javascript/nestjs_access"

private def atom_text(atom : Access::Atom) : String
  atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s
end

# Reads the decorator on a method of a one-class source that starts with
# `prelude`, and returns its values with each unresolved atom's text.
private def read_metadata(decorator : String, prelude : String = "") : Array(String)?
  source = "#{prelude}\nclass C {\n  #{decorator}\n  m() {}\n}\n"
  parsed = Noir::TsDecoratorExtractor.extract(source, "c.ts").first.methods.first.decorators.first
  NestjsAccess.metadata(parsed.name, parsed.args, parsed.text, source).try { |_, atoms| atoms.map { |atom| atom_text(atom) }.sort! }
end

private def use(text : String, *values : String) : NestjsAccess::Use
  NestjsAccess::Use.new(values.map { |value| Access::Atom.new(:role, value) }.to_a, text)
end

private def requirement(method : NestjsAccess::Use?, klass : NestjsAccess::Use?, reader : NestjsAccess::Reader?) : Array(Array(String))
  NestjsAccess.requirement(method, klass, reader).map(&.map { |atom| atom_text(atom) }.sort!)
end

private def reader(targets : NestjsAccess::Targets?, any_of : Bool?) : NestjsAccess::Reader
  NestjsAccess::Reader.new(targets, any_of)
end

describe NestjsAccess do
  describe ".metadata" do
    {
      "@Roles('admin')"                                      => ["role:admin"],
      "@Roles('admin', \"editor\")"                          => ["role:admin", "role:editor"],
      "@Roles(['admin', 'editor'])"                          => ["role:admin", "role:editor"],
      "@Roles(`admin`)"                                      => ["role:admin"],
      "@Roles(`${prefix}admin`)"                             => ["unresolved:`${prefix}admin`"],
      "@Roles('admin', Role.Admin)"                          => ["role:admin", "unresolved:Role.Admin"],
      "@Roles(...ADMINS)"                                    => ["unresolved:...ADMINS"],
      "@Roles(roleFor('x'))"                                 => ["unresolved:roleFor('x')"],
      "@Roles()"                                             => ["unresolved:@Roles()"],
      "@Permissions('posts:write')"                          => ["permission:posts:write"],
      "@RequirePermissions('a', 'b')"                        => ["permission:a", "permission:b"],
      "@Scopes('read', 'write')"                             => ["scope:read", "scope:write"],
      "@CheckPolicies(new ReadPolicy())"                     => ["unresolved:@CheckPolicies(new ReadPolicy())"],
      "@CheckAbilities({ action: 'read', subject: 'Post' })" => ["unresolved:@CheckAbilities({ action: 'read', subject: 'Post' })"],
      "@SetMetadata('roles', ['admin'])"                     => ["role:admin"],
      "@SetMetadata('roles', ROLES)"                         => ["unresolved:ROLES"],
      "@SetMetadata('roles', 'admin', 'ignored')"            => ["role:admin"],
      "@SetMetadata('roles')"                                => ["unresolved:@SetMetadata('roles')"],
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
      read_metadata("@Roles(Role.Admin, EDITOR)", prelude).should eq(["role:admin", "role:editor"])
      read_metadata("@Permissions(Perm.Write)", prelude).should eq(["permission:posts:write"])
      read_metadata("@Roles(Level.High, LOCAL, Role.Owner, Other.Admin)", prelude).should eq(["unresolved:LOCAL", "unresolved:Level.High", "unresolved:Other.Admin", "unresolved:Role.Owner"])
    end
  end

  describe ".reader" do
    guard = ->(read : String, check : String) do
      "{\n  canActivate(context) {\n    const roles = this.reflector.#{read};\n    if (!roles) return true;\n    return #{check};\n  }\n}"
    end
    some = "roles.some((role) => user.roles.includes(role))"
    every = "roles.every((role) => user.roles.includes(role))"
    {
      {"get<string[]>('roles', context.getHandler())", every}                                    => {NestjsAccess::Targets::Handler, false},
      {"get(ROLES_KEY, context.getClass())", some}                                               => {NestjsAccess::Targets::Class, true},
      {"getAllAndOverride<Role[]>(ROLES_KEY, [context.getHandler(), context.getClass()])", some} => {NestjsAccess::Targets::Override, true},
      {"getAllAndOverride(ROLES_KEY, [context.getClass(), context.getHandler()])", some}         => {nil, true},
      {"getAllAndMerge(Roles, [context.getHandler(), context.getClass()])", some}                => {NestjsAccess::Targets::Merge, true},
      {"get('roles', context.getHandler())", "roles.includes(user.role)"}                        => {NestjsAccess::Targets::Handler, true},
      {"get('roles', context.getHandler())", "check(roles, user)"}                               => {NestjsAccess::Targets::Handler, nil},
    }.each do |(read, check), (targets, any_of)|
      it "reads #{read} with #{check}" do
        NestjsAccess.reader(guard.call(read, check), Access::Kind::Role).should eq(reader(targets, any_of))
      end
    end

    it "reads no guard that makes no Reflector call on a key of that kind" do
      body = guard.call("get('roles', context.getHandler())", some)
      NestjsAccess.reader(body, Access::Kind::Permission).should be_nil
      NestjsAccess.reader("{ canActivate(ctx) { return check(ctx); } }", Access::Kind::Role).should be_nil
    end
  end

  describe ".requirement" do
    method = use("@Roles('a', 'b')", "a", "b")
    one = use("@Roles('a')", "a")
    klass = use("@Roles('c')", "c")

    it "keeps a check no visible guard runs as an alternative in every clause" do
      requirement(one, nil, nil).should eq([["role:a", "unresolved:@Roles('a')"]])
      requirement(method, nil, nil).should eq([["role:a", "role:b", "unresolved:@Roles('a', 'b')"], ["unresolved:@Roles('a', 'b')"]])
    end

    it "reads several values by the guard's check, and an unread one as an extra clause" do
      requirement(method, nil, reader(NestjsAccess::Targets::Handler, true)).should eq([["role:a", "role:b"]])
      requirement(method, nil, reader(NestjsAccess::Targets::Handler, false)).should eq([["role:a"], ["role:b"]])
      requirement(method, nil, reader(NestjsAccess::Targets::Handler, nil)).should eq([["role:a", "role:b"], ["unresolved:@Roles('a', 'b')"]])
      requirement(one, nil, reader(nil, nil)).should eq([["role:a"]])
    end

    it "counts class metadata only as the guard's Reflector call takes it" do
      requirement(nil, klass, reader(NestjsAccess::Targets::Handler, true)).should be_empty
      requirement(one, klass, reader(NestjsAccess::Targets::Handler, true)).should eq([["role:a"]])
      requirement(nil, klass, reader(NestjsAccess::Targets::Override, true)).should eq([["role:c"]])
      requirement(one, klass, reader(NestjsAccess::Targets::Override, true)).should eq([["role:a"]])
      requirement(one, klass, reader(NestjsAccess::Targets::Merge, true)).should eq([["role:a", "role:c"]])
      requirement(one, klass, reader(NestjsAccess::Targets::Merge, false)).should eq([["role:a"], ["role:c"]])
      requirement(nil, klass, reader(nil, true)).should eq([["role:c", "unresolved:@Roles('c')"]])
      requirement(one, klass, reader(nil, true)).should eq([["role:a", "unresolved:@Roles('c')"]])
      requirement(one, klass, reader(nil, false)).should eq([["role:a"], ["role:c", "unresolved:@Roles('c')"]])
    end
  end
end
