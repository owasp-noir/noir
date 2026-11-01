require "../../spec_helper"
require "../../../src/miniparsers/csharp_decl_parser"

private def parse(source : String) : Noir::CSharpDecl::Unit
  Noir::CSharpDeclParser.parse(Noir::CSharpLexer.new(source))
end

private def method(unit : Noir::CSharpDecl::Unit, name : String) : Noir::CSharpDecl::Member
  unit.types.flat_map(&.members).find! { |member| member.name == name }
end

describe Noir::CSharpDeclParser do
  it "reads namespaces, generic and partial types and their base lists" do
    unit = parse(<<-CS)
      namespace Outer
      {
          namespace Inner
          {
              public abstract partial class CrudController<T> : global::App.ApiBase<T>, IFilter where T : class, new()
              {
                  public class Nested : Base { }
              }
          }
      }
      CS
    crud = unit.types.find! { |type| type.name == "CrudController" }
    crud.namespace.should eq "Outer.Inner"
    crud.type_params.should eq "<T>"
    crud.modifiers.should eq ["public", "abstract", "partial"]
    crud.bases.should eq ["global::App.ApiBase<T>", "IFilter"]
    crud.base_name.should eq "ApiBase"
    crud.types.map(&.name).should eq ["Nested"]
    unit.top_types.map(&.name).should eq ["CrudController"]

    scoped = parse("namespace App.Web;\n[ApiController]\npublic record Dto(int Id, [property: JsonPropertyName(\"n\")] string Name) : Base(Id);\n")
    dto = scoped.types.first
    {dto.kind, dto.namespace, dto.base_name}.should eq({"record", "App.Web", "Base"})
    dto.params.not_nil!.map(&.name).should eq ["Id", "Name"]
    dto.params.not_nil![1].attributes.first.target.should eq "property"
  end

  it "reads attributes as nodes whatever the list holds" do
    unit = parse(<<-CS)
      public class C : ControllerBase
      {
          [Authorize, HttpPost("create")]
          [HttpGet(template: "named/{id}", Order = 2), Route("a,b]")]
          // [HttpPut("commented")]
          [return: NotNull]
      #if DEBUG
          [Produces("x")]
      #endif
          public IActionResult Create(int id) => Ok("}");
      }
      CS
    create = method(unit, "Create")
    create.attributes.map(&.name).should eq ["Authorize", "HttpPost", "HttpGet", "Route", "NotNull", "Produces"]
    get = create.attributes[2]
    get.argument("template").try(&.literal).should eq "named/{id}"
    get.property("Order").try(&.text).should eq "2"
    create.attributes[3].positional.first.literal.should eq "a,b]"
    create.attributes[4].target.should eq "return"
    create.attr_line.should eq 2
    create.line.should eq 9
    create.arrow.should_not be_nil
  end

  it "reads parameters with attributes, modifiers and defaults holding commas" do
    unit = parse(<<-CS)
      class C
      {
          public async Task<IActionResult>
              Search(
              [FromQuery(Name = "q")] string query = "a,b",
              [FromHeader(Name = "X-Trace")] string trace = "[x]",
              Dictionary<string, int> map = null,
              params string[] rest)
          {
              var s = "public IActionResult Fake() {";
          }
      }
      CS
    search = method(unit, "Search")
    search.return_type.should eq "Task<IActionResult>"
    search.params.map(&.name).should eq ["query", "trace", "map", "rest"]
    search.params[0].attributes.first.property("Name").try(&.literal).should eq "q"
    search.params[0].default.should eq %("a,b")
    search.params[2].type.should eq "Dictionary<string, int>"
    search.params[3].modifiers.should eq ["params"]
    unit.types.first.methods.map(&.name).should eq ["Search"]
    unit.member_at(4).should eq search
  end

  it "tells methods from constructors, operators, properties and fields" do
    unit = parse(<<-CS)
      public class V1ApiAttribute : RouteAttribute, IRouteTemplateProvider
      {
          private const string Doc = "[HttpDelete(\\"phantom\\")] public IActionResult X()";
          private const string Raw = """
              public IActionResult Raw() { }
              """;
          public V1ApiAttribute(string resource = "") : base("api/v1/" + resource) { }
          public string Template => $"api/{Name}";
          public int? Order { get; set; } = 2;
          public (int, string) Tuple() => (1, "a");
          public static bool operator ==(V1ApiAttribute a, V1ApiAttribute b) => true;
          public T Get<T>() where T : new() => new T();
      }
      CS
    type = unit.types.first
    type.members.map { |member| {member.kind, member.name} }.should eq [
      {:field, "Doc"}, {:field, "Raw"}, {:constructor, "V1ApiAttribute"}, {:property, "Template"},
      {:property, "Order"}, {:method, "Tuple"}, {:operator, "operator=="}, {:method, "Get"},
    ]
    ctor = type.constructors.first
    ctor.initializer.should eq "base"
    ctor.initializer_args.not_nil!.map(&.text).should eq [%("api/v1/" + resource)]
    type.members[3].value.should eq %($"api/{Name}")
    type.members[4].value.should eq "2"
    method(unit, "Tuple").return_type.should eq "(int, string)"
    method(unit, "Get").type_params.should eq "<T>"
  end

  it "finds the innermost type and the member at a line" do
    unit = parse("class A\n{\n    class B\n    {\n        void M() { }\n    }\n    void N() { var t = \"class Fake : Base {\"; }\n}\n")
    unit.type_at(4).try(&.name).should eq "B"
    unit.type_at(6).try(&.name).should eq "A"
    unit.member_at(6).try(&.name).should eq "N"
  end

  it "skips top-level statements without inventing members" do
    unit = parse(<<-CS)
      var app = WebApplication.CreateBuilder(args).Build();
      app.MapGet("/x", () => { return "}"; }).RequireAuthorization();
      static void Helper() { }
      public partial class Program { }
      CS
    unit.types.map(&.name).should eq ["Program"]
  end

  it "parses in linear time" do
    member = ->(i : Int32) { %(    [HttpGet("r#{i}/{id}"), Authorize(Roles = "a,b")]\n    public IActionResult A#{i}([FromQuery(Name = "q")] string q = "x,y") => Ok("} 한국어");\n) }
    source = ->(n : Int32) { "namespace N;\npublic class C : ControllerBase\n{\n" + (0...n).join { |i| member.call(i) } + "}\n" }
    small = source.call(1000)
    large = source.call(8000)
    parse(small)
    small_time = Time.measure { parse(small) }
    large_time = Time.measure { parse(large) }
    parse(large).types.first.methods.size.should eq 8000
    (large_time / small_time).should be < 24
  end
end
