require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/csharp/common"

private class StringValueProbe
  include Analyzer::CSharp::Common

  def initialize(@sources : Hash(String, String))
  end

  def value(expr : String, file : String) : String?
    csharp_string_value(expr, file)
  end

  def read_file_content(path : String) : String
    @sources[path]
  end

  def get_files_by_extension(extension : String) : Array(String)
    @sources.keys.select(&.ends_with?(extension))
  end

  def base_relative_path(path : String) : String
    path
  end
end

describe "Analyzer::CSharp::Common#csharp_string_value concatenation" do
  routes = <<-CS
    namespace App;

    public static class ApiRoutes
    {
        public const string Root = "api";
        public const string Version = "v1";
        public const string Base = Root + "/" + Version;
        public const string Id = "{id}";
    }
    CS
  probe = StringValueProbe.new({"/app/ApiRoutes.cs" => routes, "/app/Program.cs" => "var x = 1;\n"})

  it "joins a literal and a constant" do
    probe.value(%q("prefix/" + ApiRoutes.Root), "/app/Program.cs").should eq("prefix/api")
  end

  it "joins a constant whose own value is a concatenation" do
    probe.value(%q(ApiRoutes.Base + "/posts"), "/app/Program.cs").should eq("api/v1/posts")
  end

  it "joins a constant and an interpolated string" do
    probe.value(%q(ApiRoutes.Base + $"/items/{ApiRoutes.Id}/{{raw}}"), "/app/Program.cs").should eq("api/v1/items/{id}/{raw}")
  end

  it "does not split at a + inside a string or a hole" do
    probe.value(%q("a+b" + $"{ApiRoutes.Root + "x"}"), "/app/Program.cs").should eq("a+bapix")
  end

  it "is nil when one operand cannot be read" do
    probe.value(%q(ApiRoutes.Base + name), "/app/Program.cs").should be_nil
    probe.value(%q(ApiRoutes.Base + 1), "/app/Program.cs").should be_nil
    probe.value(%q(+ApiRoutes.Base), "/app/Program.cs").should be_nil
  end
end
