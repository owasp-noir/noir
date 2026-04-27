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

  describe "#resolve_relative_import" do
    it "resolves a sibling file by adding a candidate extension" do
      with_tmpdir do |root|
        Dir.mkdir_p(File.join(root, "src"))
        from_file = File.join(root, "src", "index.ts")
        target = File.join(root, "src", "users.ts")
        File.write(from_file, "")
        File.write(target, "")

        Noir::ImportGraph.resolve_relative_import(from_file, "./users").should eq(target)
      end
    end

    it "honours an explicit extension on the specifier" do
      with_tmpdir do |root|
        Dir.mkdir_p(File.join(root, "src"))
        from_file = File.join(root, "src", "index.ts")
        target = File.join(root, "src", "users.ts")
        # A `.js` sibling exists but the specifier requests `.ts`.
        File.write(from_file, "")
        File.write(target, "")
        File.write(File.join(root, "src", "users.js"), "")

        Noir::ImportGraph.resolve_relative_import(from_file, "./users.ts").should eq(target)
      end
    end

    it "falls back to <dir>/index.<ext> for directory specifiers" do
      with_tmpdir do |root|
        Dir.mkdir_p(File.join(root, "src", "routes"))
        from_file = File.join(root, "src", "index.ts")
        target = File.join(root, "src", "routes", "index.ts")
        File.write(from_file, "")
        File.write(target, "")

        Noir::ImportGraph.resolve_relative_import(from_file, "./routes").should eq(target)
      end
    end

    it "walks up parent directories with `..`" do
      with_tmpdir do |root|
        Dir.mkdir_p(File.join(root, "src", "deep"))
        from_file = File.join(root, "src", "deep", "child.ts")
        target = File.join(root, "src", "shared.ts")
        File.write(from_file, "")
        File.write(target, "")

        Noir::ImportGraph.resolve_relative_import(from_file, "../shared").should eq(target)
      end
    end

    it "tries extensions in priority order" do
      with_tmpdir do |root|
        Dir.mkdir_p(File.join(root, "src"))
        from_file = File.join(root, "src", "index.ts")
        ts_target = File.join(root, "src", "users.ts")
        js_target = File.join(root, "src", "users.js")
        File.write(from_file, "")
        File.write(ts_target, "")
        File.write(js_target, "")

        # `.ts` precedes `.js` in `JS_RESOLVE_EXTENSIONS`, so the
        # TypeScript file wins.
        Noir::ImportGraph.resolve_relative_import(from_file, "./users").should eq(ts_target)
      end
    end

    it "returns nil for bare specifiers (node_modules)" do
      with_tmpdir do |root|
        from_file = File.join(root, "index.ts")
        File.write(from_file, "")
        Noir::ImportGraph.resolve_relative_import(from_file, "lodash").should be_nil
        Noir::ImportGraph.resolve_relative_import(from_file, "@hapi/hapi").should be_nil
      end
    end

    it "returns nil when nothing on disk matches" do
      with_tmpdir do |root|
        from_file = File.join(root, "index.ts")
        File.write(from_file, "")
        Noir::ImportGraph.resolve_relative_import(from_file, "./missing").should be_nil
      end
    end

    it "accepts a custom extension list" do
      with_tmpdir do |root|
        from_file = File.join(root, "index.rb")
        target = File.join(root, "users.rb")
        File.write(from_file, "")
        File.write(target, "")

        Noir::ImportGraph.resolve_relative_import(from_file, "./users", extensions: ["rb"]).should eq(target)
      end
    end

    describe "with boundary" do
      it "allows specifiers that resolve inside the boundary" do
        with_tmpdir do |root|
          Dir.mkdir_p(File.join(root, "src", "sub"))
          from_file = File.join(root, "src", "sub", "index.ts")
          target = File.join(root, "src", "shared.ts")
          File.write(from_file, "")
          File.write(target, "")

          Noir::ImportGraph.resolve_relative_import(
            from_file, "../shared", boundary: root
          ).should eq(target)
        end
      end

      it "rejects specifiers that escape outside the boundary" do
        with_tmpdir do |outside|
          File.write(File.join(outside, "secret.ts"), "")
          with_tmpdir do |project|
            Dir.mkdir_p(File.join(project, "src"))
            from_file = File.join(project, "src", "index.ts")
            File.write(from_file, "")

            # Compute the relative-traversal specifier from
            # `from_file` (deep inside `project`) up to the
            # `secret.ts` file sitting in a sibling tmpdir.
            specifier = Path[outside, "secret"].relative_to(File.dirname(from_file)).to_s
            Noir::ImportGraph.resolve_relative_import(
              from_file, specifier, boundary: project
            ).should be_nil
          end
        end
      end

      it "treats boundary as inclusive of itself" do
        with_tmpdir do |root|
          # `from_file` sits at the boundary root, importing a
          # sibling that is also at the root — should resolve.
          from_file = File.join(root, "index.ts")
          target = File.join(root, "users.ts")
          File.write(from_file, "")
          File.write(target, "")

          Noir::ImportGraph.resolve_relative_import(
            from_file, "./users", boundary: root
          ).should eq(target)
        end
      end

      it "rejects when the from_file itself sits outside the boundary" do
        # Defence-in-depth: even if the specifier is harmless,
        # passing a `from_file` that's outside `boundary` shouldn't
        # let the resolver leak files reachable relative to it.
        with_tmpdir do |project|
          with_tmpdir do |elsewhere|
            from_file = File.join(elsewhere, "index.ts")
            target = File.join(elsewhere, "neighbour.ts")
            File.write(from_file, "")
            File.write(target, "")

            Noir::ImportGraph.resolve_relative_import(
              from_file, "./neighbour", boundary: project
            ).should be_nil
          end
        end
      end
    end
  end
end

describe Noir::ImportGraph::Python do
  describe "#find_imported_modules" do
    it "resolves `from package.module import name` to a file path" do
      with_tmpdir do |root|
        Dir.mkdir_p(File.join(root, "models"))
        target = File.join(root, "models", "user.py")
        from_file = File.join(root, "app.py")
        File.write(target, "def get_user(): pass\n")
        # `get_user` chosen instead of `User` so the case-insensitive
        # macOS filesystem doesn't collapse `User.py` and `user.py`
        # into the same `File.exists?` truthy result inside the
        # PackageType::FILE / CODE classifier.
        content = "from models.user import get_user\n"
        File.write(from_file, content)

        result = Noir::ImportGraph::Python.find_imported_modules(root, from_file, content)
        result.should eq({"get_user" => {target, Noir::ImportGraph::Python::PackageType::CODE}})
      end
    end

    it "honours `as` aliases in the imported-name key" do
      with_tmpdir do |root|
        Dir.mkdir_p(File.join(root, "lib"))
        target = File.join(root, "lib", "helpers.py")
        from_file = File.join(root, "main.py")
        File.write(target, "")
        content = "from lib.helpers import format as fmt\n"
        File.write(from_file, content)

        result = Noir::ImportGraph::Python.find_imported_modules(root, from_file, content)
        result.has_key?("fmt").should be_true
        result.has_key?("format").should be_false
      end
    end

    it "resolves relative imports `from . import x` against the file's directory" do
      with_tmpdir do |root|
        Dir.mkdir_p(File.join(root, "pkg"))
        sibling = File.join(root, "pkg", "sibling.py")
        from_file = File.join(root, "pkg", "main.py")
        File.write(sibling, "")
        content = "from . import sibling\n"
        File.write(from_file, content)

        result = Noir::ImportGraph::Python.find_imported_modules(root, from_file, content)
        # The dotted-walk maps the bare module name to the package
        # path — `py_path` is empty (no leaf-module hit) when we
        # land on a directory, but the entry exists.
        result.has_key?("sibling").should be_true
      end
    end

    it "handles parenthesised multi-line imports" do
      with_tmpdir do |root|
        Dir.mkdir_p(File.join(root, "models"))
        a = File.join(root, "models", "a.py")
        b = File.join(root, "models", "b.py")
        from_file = File.join(root, "app.py")
        [a, b].each { |f| File.write(f, "") }
        content = "from models import (\n  a,\n  b,\n)\n"
        File.write(from_file, content)

        result = Noir::ImportGraph::Python.find_imported_modules(root, from_file, content)
        result.has_key?("a").should be_true
        result.has_key?("b").should be_true
      end
    end

    it "returns an empty map when no imports resolve to files" do
      with_tmpdir do |root|
        from_file = File.join(root, "app.py")
        content = "from missing.package import nothing\n"
        File.write(from_file, content)

        Noir::ImportGraph::Python.find_imported_modules(root, from_file, content).should be_empty
      end
    end

    it "reads from disk when content is omitted" do
      with_tmpdir do |root|
        Dir.mkdir_p(File.join(root, "lib"))
        target = File.join(root, "lib", "x.py")
        File.write(target, "")
        from_file = File.join(root, "app.py")
        File.write(from_file, "from lib.x import x\n")

        result = Noir::ImportGraph::Python.find_imported_modules(root, from_file)
        result.has_key?("x").should be_true
      end
    end
  end

  describe "#find_imported_package" do
    it "marks leaf modules as PackageType::FILE" do
      with_tmpdir do |root|
        target = File.join(root, "user.py")
        File.write(target, "")
        result = Noir::ImportGraph::Python.find_imported_package(root, "user")
        result.size.should eq(1)
        _, _, package_type = result.first
        package_type.should eq(Noir::ImportGraph::Python::PackageType::FILE)
      end
    end

    it "returns an empty array for unresolvable dotted paths" do
      with_tmpdir do |root|
        Noir::ImportGraph::Python.find_imported_package(root, "no.such.module").should be_empty
      end
    end
  end
end
