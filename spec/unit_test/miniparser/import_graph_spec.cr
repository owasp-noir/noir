require "spec"
require "file_utils"
require "../../../src/miniparsers/import_graph"

private def collect(path, package_name, imports, extension)
  visited = [] of String
  Noir::ImportGraph.related_files(path, package_name, imports, extension) do |file|
    visited << file
  end
  visited
end

private def with_tmpdir(&)
  root = File.join(Dir.tempdir, "noir-importgraph-#{Random::Secure.hex(8)}")
  Dir.mkdir_p(root)
  begin
    yield root
  ensure
    FileUtils.rm_rf(root) if Dir.exists?(root)
  end
end

describe Noir::ImportGraph do
  describe "#source_root_for" do
    it "infers the root by stripping the package path from the directory" do
      Noir::ImportGraph.source_root_for(
        "/work/proj/src/main/java/com/foo/Bar.java", "com.foo"
      ).should eq("/work/proj/src/main/java")
    end

    it "returns '.' when the package consumes the whole directory" do
      Noir::ImportGraph.source_root_for("com/foo/Bar.kt", "com.foo").should eq(".")
    end

    it "returns nil when the package path doesn't trail the directory" do
      Noir::ImportGraph.source_root_for(
        "/work/proj/src/com/foo/Bar.java", "com.example"
      ).should be_nil
    end

    it "returns nil when the directory is shorter than the package" do
      Noir::ImportGraph.source_root_for("Bar.java", "com.foo").should be_nil
    end
  end

  describe "#related_files" do
    it "yields the file itself, then same-directory siblings, then resolved imports" do
      with_tmpdir do |root|
        java_root = File.join(root, "src", "main", "java")
        Dir.mkdir_p(File.join(java_root, "com", "example", "controller"))
        Dir.mkdir_p(File.join(java_root, "com", "example", "model"))

        controller = File.join(java_root, "com", "example", "controller", "UserController.java")
        sibling = File.join(java_root, "com", "example", "controller", "Helper.java")
        single_import = File.join(java_root, "com", "example", "model", "User.java")
        wildcard_neighbour = File.join(java_root, "com", "example", "model", "Profile.java")
        unrelated = File.join(java_root, "com", "example", "model", "Profile.kt")

        [controller, sibling, single_import, wildcard_neighbour, unrelated].each do |f|
          File.write(f, "")
        end

        imports = [
          Noir::ImportGraph::ImportRef.new("com.example.model.User", false),
          Noir::ImportGraph::ImportRef.new("com.example.model", true),
        ]

        visited = collect(controller, "com.example.controller", imports, "java")
        visited.should contain(controller)
        visited.should contain(sibling)
        visited.should contain(single_import)
        visited.should contain(wildcard_neighbour)
        visited.should_not contain(unrelated)
        visited.size.should eq(visited.uniq.size) # no duplicates
      end
    end

    it "still yields siblings when the package declaration is empty" do
      with_tmpdir do |root|
        a = File.join(root, "A.java")
        b = File.join(root, "B.java")
        File.write(a, "")
        File.write(b, "")

        visited = collect(a, "", [] of Noir::ImportGraph::ImportRef, "java")
        visited.should contain(a)
        visited.should contain(b)
      end
    end

    it "skips imports that don't resolve to existing files" do
      with_tmpdir do |root|
        java_root = File.join(root, "src")
        Dir.mkdir_p(File.join(java_root, "com", "example"))
        file = File.join(java_root, "com", "example", "Foo.java")
        File.write(file, "")

        imports = [Noir::ImportGraph::ImportRef.new("com.example.Missing", false)]
        visited = collect(file, "com.example", imports, "java")
        visited.should eq([file])
      end
    end

    it "deduplicates files reachable through multiple paths" do
      with_tmpdir do |root|
        java_root = File.join(root, "src")
        Dir.mkdir_p(File.join(java_root, "com", "example"))
        a = File.join(java_root, "com", "example", "A.java")
        b = File.join(java_root, "com", "example", "B.java")
        [a, b].each { |f| File.write(f, "") }

        # B is both a same-package sibling and an explicit import.
        imports = [Noir::ImportGraph::ImportRef.new("com.example.B", false)]
        visited = collect(a, "com.example", imports, "java")
        visited.size.should eq(visited.uniq.size)
        visited.count(b).should eq(1)
      end
    end
  end
end
