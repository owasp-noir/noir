require "../../spec_helper"
require "../../../src/miniparsers/csharp_attribute_routes"

private def table_for(source : String) : Noir::CSharpAttributeRoutes
  table = Noir::CSharpAttributeRoutes.new
  lexer = Noir::CSharpLexer.new(source)
  Noir::CSharpTypeExtractor.extract(lexer).each { |type| table.add(lexer, type) }
  table
end

# The usage `[name(args)]`, parsed the way a controller's attribute is.
private def usage(name : String, args : Array(String) = [] of String) : Noir::CSharpDecl::Attribute
  source = "[#{name}#{args.empty? ? "" : "(#{args.join(", ")})"}] class C { }"
  Noir::CSharpDeclParser.parse(Noir::CSharpLexer.new(source)).types.first.attributes.first
end

VERSIONED = <<-CS
  public class VersionedApiControllerAttribute : Attribute, IRouteTemplateProvider
  {
      public const string CONTROLLER_RESOURCE = "[controller]";
      public VersionedApiControllerAttribute(int version, string resource = CONTROLLER_RESOURCE)
      {
          Template = $"api/v{version}/{resource}";
      }
      public string Template { get; }
  }
  public class V3ApiControllerAttribute : VersionedApiControllerAttribute
  {
      public V3ApiControllerAttribute(string resource = "[controller]")
          : base(3, resource)
      {
      }
  }
  public class RestGetByIdAttribute : Attribute, IActionHttpMethodProvider, IRouteTemplateProvider
  {
      public IEnumerable<string> HttpMethods => new[] { "GET" };
      public string Template => "{id:int}";
  }
  public class RestPutByIdAttribute : HttpPutAttribute
  {
      public RestPutByIdAttribute() : base("{id:int?}") { }
  }
  public class RestPostByIdAttribute : HttpPostAttribute
  {
  }
  public class LabelAttribute : Attribute
  {
      public string Template => "labelled";
  }
  CS

describe Noir::CSharpAttributeRoutes do
  table = table_for(VERSIONED)

  it "follows the constructor chain into an interpolated Template" do
    table.resolve(usage("V3ApiController", ["\"series\""])).should eq Noir::CSharpAttributeRoutes::Result.new(nil, "api/v3/series")
    table.resolve(usage("V3ApiController", [] of String)).should eq Noir::CSharpAttributeRoutes::Result.new(nil, "api/v3/[controller]")
    table.resolve(usage("V3ApiController", ["resource: \"queue\""])).should eq Noir::CSharpAttributeRoutes::Result.new(nil, "api/v3/queue")
  end

  it "reads a verb and template from the provider interface members or the built-in base" do
    table.resolve(usage("RestGetById", [] of String)).should eq Noir::CSharpAttributeRoutes::Result.new("GET", "{id:int}")
    table.resolve(usage("RestPutById", [] of String)).should eq Noir::CSharpAttributeRoutes::Result.new("PUT", "{id:int?}")
    table.resolve(usage("RestPostById", [] of String)).should eq Noir::CSharpAttributeRoutes::Result.new("POST", nil)
  end

  it "leaves out an attribute that only has a Template property, and an argument it cannot read" do
    table.resolve(usage("Label", [] of String)).should be_nil
    table.route_names.sort!.should eq ["RestGetById", "RestPostById", "RestPutById", "V3ApiController", "VersionedApiController"]
    # `Prefix.Value` is a constant of another class: no template rather than a wrong one.
    table.resolve(usage("V3ApiController", ["Prefix.Value"])).try(&.template).should be_nil
  end

  it "takes a name two projects define from the usage's own project, and refuses when that does not settle it" do
    source = ->(prefix : String) { "public class ApiRouteAttribute : Attribute, IRouteTemplateProvider\n{\n public ApiRouteAttribute(string r) { Template = $\"#{prefix}/{r}\"; }\n public string Template { get; }\n}\n" }
    scoped = Noir::CSharpAttributeRoutes.new
    {"a" => "alpha", "b" => "beta"}.each do |scope, prefix|
      lexer = Noir::CSharpLexer.new(source.call(prefix))
      Noir::CSharpTypeExtractor.extract(lexer).each { |type| scoped.add(lexer, type, scope) }
    end
    scoped.resolve(usage("ApiRoute", ["\"x\""]), "a").try(&.template).should eq "alpha/x"
    scoped.resolve(usage("ApiRoute", ["\"x\""]), "b").try(&.template).should eq "beta/x"
    scoped.resolve(usage("ApiRoute", ["\"x\""]), "c").should be_nil
  end

  it "ignores property assignments and a filter that merely has a Template" do
    other = table_for("public class RestGetAttribute : HttpGetAttribute { public RestGetAttribute(string t) : base(t) { } }\npublic class ViewTemplateAttribute : ResultFilterAttribute { public string Template => \"x\"; }")
    other.resolve(usage("RestGet", ["\"ord\"", "Order = 2", "Name = \"n\""])).should eq Noir::CSharpAttributeRoutes::Result.new("GET", "ord")
    other.resolve(usage("ViewTemplate", [] of String)).should be_nil
  end

  it "binds arguments split at top-level commas only" do
    other = table_for("public class PathAttribute : RouteAttribute { public PathAttribute(string a, string b = \"z\") : base(a + b) { } }\npublic class SegAttribute : HttpGetAttribute { public SegAttribute(string t, string u = \"\") : base(t) { } }")
    other.resolve(usage("Seg", [%q("a,b"), "Order = 1", %q(u: f(1, 2))])).should eq Noir::CSharpAttributeRoutes::Result.new("GET", "a,b")
  end
end
