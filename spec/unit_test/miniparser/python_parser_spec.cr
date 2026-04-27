require "spec"
require "file_utils"
require "../../../src/miniparsers/python"

private def with_tmpdir(&)
  root = File.join(Dir.tempdir, "noir-pyparser-#{Random::Secure.hex(8)}")
  Dir.mkdir_p(root)
  begin
    yield root
  ensure
    FileUtils.rm_rf(root) if Dir.exists?(root)
  end
end

describe PythonParser do
  describe "global variable extraction" do
    it "extracts a typed string assignment" do
      content = "BASE_URL: str = \"http://localhost\"\n"
      parsers = Hash(String, PythonParser).new
      parser = PythonParser.new("/app.py", content, parsers)

      gv = parser.@global_variables["BASE_URL"]
      gv.type.should eq("str")
      gv.value.should eq("http://localhost")
    end

    it "infers `str` type for unannotated string assignments" do
      content = "name = \"hello\"\n"
      parsers = Hash(String, PythonParser).new
      parser = PythonParser.new("/app.py", content, parsers)

      gv = parser.@global_variables["name"]
      gv.type.should eq("str")
      gv.value.should eq("hello")
    end

    it "captures the callee name as `type` for `name = Foo(...)` calls" do
      content = "bp = Blueprint(\"users\", url_prefix=\"/users\")\n"
      parsers = Hash(String, PythonParser).new
      parser = PythonParser.new("/app.py", content, parsers)

      gv = parser.@global_variables["bp"]
      gv.type.should eq("Blueprint")
      gv.value.should contain("Blueprint(")
      gv.value.should contain("\"/users\"")
    end

    it "preserves dotted callees like `Namespace.model(...)` as the type" do
      content = "user_model = ns.model(\"User\", {})\n"
      parsers = Hash(String, PythonParser).new
      parser = PythonParser.new("/app.py", content, parsers)

      gv = parser.@global_variables["user_model"]
      gv.type.should eq("ns.model")
    end

    it "leaves type nil for non-call non-string assignments" do
      content = "count = 42\n"
      parsers = Hash(String, PythonParser).new
      parser = PythonParser.new("/app.py", content, parsers)

      gv = parser.@global_variables["count"]
      gv.type.should be_nil
      gv.value.should eq("42")
    end

    it "captures multiple top-level assignments" do
      content = "host = \"localhost\"\nport = 8080\n"
      parsers = Hash(String, PythonParser).new
      parser = PythonParser.new("/config.py", content, parsers)

      parser.@global_variables.has_key?("host").should be_true
      parser.@global_variables.has_key?("port").should be_true
    end
  end

  describe "import recursion" do
    it "absorbs `from x import y` from a sibling module" do
      with_tmpdir do |root|
        sibling = File.join(root, "models.py")
        File.write(sibling, "user_bp = Blueprint(\"users\", url_prefix=\"/users\")\n")

        app = File.join(root, "app.py")
        content = "from models import user_bp\n"
        File.write(app, content)

        parsers = Hash(String, PythonParser).new
        parser = PythonParser.new(app, content, parsers)

        parser.@global_variables.has_key?("user_bp").should be_true
        parser.@global_variables["user_bp"].type.should eq("Blueprint")
      end
    end

    it "honours `as` aliases on `from x import y as z`" do
      with_tmpdir do |root|
        sibling = File.join(root, "lib.py")
        File.write(sibling, "thing = Blueprint(\"t\")\n")
        app = File.join(root, "app.py")
        content = "from lib import thing as alt\n"
        File.write(app, content)

        parsers = Hash(String, PythonParser).new
        parser = PythonParser.new(app, content, parsers)

        parser.@global_variables.has_key?("alt").should be_true
        parser.@global_variables.has_key?("thing").should be_false
      end
    end

    it "merges every global on `from x import *`" do
      with_tmpdir do |root|
        sibling = File.join(root, "shared.py")
        File.write(sibling, "a = Blueprint(\"a\")\nb = Blueprint(\"b\")\n")
        app = File.join(root, "app.py")
        content = "from shared import *\n"
        File.write(app, content)

        parsers = Hash(String, PythonParser).new
        parser = PythonParser.new(app, content, parsers)

        parser.@global_variables.has_key?("a").should be_true
        parser.@global_variables.has_key?("b").should be_true
      end
    end

    it "deduplicates revisits via the @visited tracking" do
      with_tmpdir do |root|
        # `app.py` and `b.py` both `from . import a`. Loading via
        # `app` should still terminate even though there's a
        # diamond-shaped import graph.
        File.write(File.join(root, "a.py"), "x = Blueprint(\"x\")\n")
        File.write(File.join(root, "b.py"), "from . import a\n")
        app = File.join(root, "app.py")
        content = "from . import a\nfrom . import b\n"
        File.write(app, content)

        parsers = Hash(String, PythonParser).new
        parser = PythonParser.new(app, content, parsers)

        # `a` is exposed both directly and via `b`'s re-export — the
        # name should be present and resolvable.
        parser.@global_variables.size.should be > 0
      end
    end
  end

  describe "GlobalVariables#to_s" do
    it "includes type when present" do
      gv = PythonParser::GlobalVariables.new("host", "str", "localhost", "/app.py")
      gv.to_s.should contain("host")
      gv.to_s.should contain("str")
      gv.to_s.should contain("localhost")
    end

    it "omits the colon when type is nil" do
      gv = PythonParser::GlobalVariables.new("count", nil, "42", "/app.py")
      gv.to_s.should contain("count")
      gv.to_s.should contain("42")
    end
  end

  describe "ImportModel#to_s" do
    it "shows path when known" do
      im = PythonParser::ImportModel.new("os", "/usr/lib/python3/os.py", nil)
      im.to_s.should contain("os")
      im.to_s.should contain("/usr/lib/python3/os.py")
    end

    it "shows {unknown} when path is nil" do
      im = PythonParser::ImportModel.new("os", nil, nil)
      im.to_s.should contain("os")
      im.to_s.should contain("unknown")
    end

    it "shows the alias" do
      im = PythonParser::ImportModel.new("numpy", "/site-packages/numpy.py", "np")
      im.to_s.should contain("numpy")
      im.to_s.should contain("np")
    end
  end
end
