require "../../spec_helper"
require "../../../src/output_builder/access_matrix"

private def render_matrix(endpoints : Array(Endpoint)) : String
  builder = OutputBuilderAccessMatrix.new(create_test_options)
  builder.io = IO::Memory.new
  builder.print(endpoints)
  builder.io.to_s
end

private def guarded(method : String, url : String, *tags : Tag) : Endpoint
  endpoint = Endpoint.new(url, method)
  tags.each { |tag| endpoint.add_tag(tag) }
  endpoint
end

private def requiring(*clauses : Array(Access::Atom)) : Tag
  Tag.new("auth", "d", "spring_auth", requires: clauses.map { |atoms| Access::Clause.new(atoms, "s") }.to_a)
end

describe OutputBuilderAccessMatrix do
  admin = Access::Atom.new(:role, "ADMIN")
  write = Access::Atom.new(:permission, "posts:write")
  hostile = Access::Atom.new(:role, "a|b`c")

  it "renders one row per served endpoint, a column per principal and the requirement" do
    client_call = Endpoint.new("/upstream/users", "GET")
    client_call.internal = true
    output = render_matrix([
      guarded("DELETE", "/api/admin/users/{id}", requiring([admin], [Access::Atom.new(:authenticated)])),
      guarded("PUT", "/api/posts/{id}", requiring([admin, write], [Access::Atom.new(:unresolved, "@acl.check(#id)")])),
      guarded("GET", "/me", Tag.new("auth", "Protected by @UseGuards", "nestjs_auth")),
      Endpoint.new("/api/public/health", "GET"),
      guarded("POST", "/login", Tag.new("anonymous", "permitAll()", "spring_auth")),
      client_call,
      guarded("GET", "/x", requiring([hostile])),
    ])

    output.should eq(<<-MD)
      | Endpoint | `anonymous` | `authenticated` | `role:ADMIN` | ``role:a\\|b`c`` | `permission:posts:write` | Requires |
      | --- | --- | --- | --- | --- | --- | --- |
      | `DELETE /api/admin/users/{id}` | - | - | Y | - | - | `role:ADMIN & authenticated` |
      | `PUT /api/posts/{id}` | - | - | ? | - | ? | `(role:ADMIN \\| permission:posts:write) & unresolved` |
      | `GET /me` | - | ? | ? | ? | ? | `authenticated & unresolved` |
      | `GET /api/public/health` | Y | Y | Y | Y | Y | no guard found |
      | `POST /login` | Y | Y | Y | Y | Y | `anonymous` |
      | `GET /x` | - | - | - | Y | - | ``role:a\\|b`c`` |

      Y allowed, - denied, ? unknown (a guard noir could not read)

      MD

    output.lines.first(8).each { |line| line.scan(/(?<!\\)\|/).size.should eq(8), line }
  end

  it "prints the header and legend for no endpoints" do
    render_matrix([] of Endpoint).should eq(<<-MD)
      | Endpoint | `anonymous` | `authenticated` | Requires |
      | --- | --- | --- | --- |

      Y allowed, - denied, ? unknown (a guard noir could not read)

      MD
  end
end
