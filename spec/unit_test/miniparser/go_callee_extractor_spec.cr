require "../../spec_helper"
require "../../../src/miniparsers/go_callee_extractor"

describe Noir::GoCalleeExtractor do
  describe ".collect_function_bodies" do
    it "indexes every top-level function declaration by name" do
      source = <<-GO
      package handlers

      func Show(c *gin.Context) {
        c.JSON(200, "ok")
      }

      func Update(c *gin.Context) {
        c.JSON(200, "ok")
      }

      func helper() {}
      GO

      bodies = Noir::GoCalleeExtractor.collect_function_bodies(source, "handlers.go")
      bodies.keys.sort!.should eq(["Show", "Update", "helper"])
      bodies["Show"].file_path.should eq("handlers.go")
      bodies["Show"].source.should contain("c.JSON(200, \"ok\")")
    end

    it "first definition wins when a name is declared twice" do
      # Go itself rejects this at build time, but the extractor is
      # asked to be resilient against malformed snippets.
      source = <<-GO
      package x
      func Foo() { return }
      func Foo() { return }
      GO

      bodies = Noir::GoCalleeExtractor.collect_function_bodies(source, "x.go")
      bodies.size.should eq(1)
      bodies.has_key?("Foo").should be_true
    end

    it "returns an empty map for source with no functions" do
      Noir::GoCalleeExtractor.collect_function_bodies("package x\n", "x.go").should be_empty
    end

    it "records the 0-based start row of the func keyword" do
      source = <<-GO
      package handlers


      func Show(c *gin.Context) {
        c.JSON(200, "ok")
      }
      GO

      bodies = Noir::GoCalleeExtractor.collect_function_bodies(source, "handlers.go")
      bodies["Show"].start_row.should eq(3)
    end
  end

  describe ".package_function_bodies" do
    it "groups per-file function bodies by directory" do
      bodies = Noir::GoCalleeExtractor.package_function_bodies({
        "app/handlers/users.go"  => "package handlers\nfunc UserShow() {}\n",
        "app/handlers/orders.go" => "package handlers\nfunc OrderList() {}\n",
        "app/server/main.go"     => "package server\nfunc Boot() {}\n",
      })

      bodies.keys.sort!.should eq(["app/handlers", "app/server"])
      bodies["app/handlers"].keys.sort!.should eq(["OrderList", "UserShow"])
      bodies["app/server"].keys.should eq(["Boot"])
    end

    it "earlier file wins on name collisions within a directory" do
      bodies = Noir::GoCalleeExtractor.package_function_bodies({
        "pkg/a.go" => "package p\nfunc Handler() {}\n",
        "pkg/b.go" => "package p\nfunc Handler() {}\n",
      })

      pkg = bodies["pkg"]
      pkg.size.should eq(1)
      # First file in iteration order wins so cross-file lookups are
      # deterministic.
      pkg["Handler"].file_path.should eq("pkg/a.go")
    end

    it "omits directories whose files declared no functions" do
      bodies = Noir::GoCalleeExtractor.package_function_bodies({
        "pkg/empty.go" => "package p\n",
      })
      bodies.should be_empty
    end
  end

  describe ".package_function_bodies_if" do
    it "returns an empty map immediately when enabled=false" do
      bodies = Noir::GoCalleeExtractor.package_function_bodies_if(false, {
        "pkg/a.go" => "package p\nfunc Handler() {}\n",
      })
      bodies.should be_empty
    end

    it "delegates to package_function_bodies when enabled=true" do
      bodies = Noir::GoCalleeExtractor.package_function_bodies_if(true, {
        "pkg/a.go" => "package p\nfunc Handler() {}\n",
      })
      bodies["pkg"]["Handler"].file_path.should eq("pkg/a.go")
    end
  end

  describe ".function_bodies_for_directory" do
    it "returns the body map for the requested directory" do
      package_bodies = Noir::GoCalleeExtractor.package_function_bodies({
        "pkg/a.go" => "package p\nfunc Handler() {}\n",
      })
      Noir::GoCalleeExtractor.function_bodies_for_directory(package_bodies, "pkg")
        .keys.should eq(["Handler"])
    end

    it "returns an empty map for an unknown directory rather than nil" do
      Noir::GoCalleeExtractor.function_bodies_for_directory(
        Hash(String, Hash(String, Noir::GoCalleeExtractor::FunctionBody)).new,
        "nowhere"
      ).should be_empty
    end
  end

  describe ".callees_for_routes" do
    it "returns an empty map when no route rows were supplied" do
      Noir::GoCalleeExtractor.callees_for_routes(
        "package x\n", "x.go", Set(Int32).new, Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      ).should be_empty
    end

    it "walks an inline closure handler and reports its callees" do
      source = <<-GO
      package main

      func register(app *gin.Engine) {
        app.GET("/users", func(c *gin.Context) {
          user := lookupUser(c)
          c.JSON(200, user)
        })
      }
      GO

      # The `app.GET(...)` call sits on the row that has `app.GET`.
      # Find it dynamically — exact row depends on the heredoc.
      target_row = source.lines.index { |l| l.includes?("app.GET(") }.not_nil!
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source, "main.go", Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      )
      names = callees[target_row].map(&.[0])

      names.should contain("lookupUser")
      # c.JSON is a method on the framework receiver — it's a useful
      # signal so it must be retained (only builtins / primitives are
      # filtered).
      names.should contain("c.JSON")
    end

    it "filters Go builtins out of the callee list" do
      source = <<-GO
      package main

      func register(app *gin.Engine) {
        app.GET("/items", func(c *gin.Context) {
          n := len(items)
          out := make([]int, 0)
          c.JSON(200, n)
        })
      }
      GO

      target_row = source.lines.index { |l| l.includes?("app.GET(") }.not_nil!
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source, "main.go", Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      )
      names = callees[target_row]?.try(&.map(&.[0])) || [] of String

      names.should_not contain("len")
      names.should_not contain("make")
      names.should contain("c.JSON")
    end

    it "resolves a same-file identifier handler against local functions" do
      source = <<-GO
      package main

      func showUser(c *gin.Context) {
        user := lookupUser(c)
        c.JSON(200, user)
      }

      func register(app *gin.Engine) {
        app.GET("/users", showUser)
      }
      GO

      target_row = source.lines.index { |l| l.includes?("app.GET(") }.not_nil!
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source, "main.go", Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      )
      names = callees[target_row].map(&.[0])

      names.should contain("lookupUser")
      names.should contain("c.JSON")
    end
  end
end
