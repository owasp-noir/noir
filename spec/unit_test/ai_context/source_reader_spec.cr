require "../../spec_helper"
require "../../../src/ai_context/source_reader"

# Writes `content` to a uniquely-named temp file, yields the path, and
# removes it afterwards. Paths are unique per example so the process-wide
# `CodeLocator` cache cannot leak between them.
private def with_source_file(content : String, ext = ".txt", &)
  path = File.join(Dir.tempdir, "noir-source-reader-#{Process.pid}-#{Random.rand(1_000_000)}#{ext}")
  File.write(path, content)
  begin
    yield path
  ensure
    File.delete(path) if File.exists?(path)
  end
end

describe NoirAIContext::SourceReader do
  describe "#snippet_for" do
    it "returns nil without a path" do
      NoirAIContext::SourceReader.new.snippet_for(nil, 3, 2).should be_nil
    end

    it "returns nil without a line" do
      with_source_file("a\nb\nc\n") do |path|
        NoirAIContext::SourceReader.new.snippet_for(path, nil, 2).should be_nil
      end
    end

    it "returns nil for a line number below 1" do
      with_source_file("a\nb\nc\n") do |path|
        NoirAIContext::SourceReader.new.snippet_for(path, 0, 2).should be_nil
      end
    end

    it "returns nil for a line past the end of the file" do
      with_source_file("a\nb\nc\n") do |path|
        NoirAIContext::SourceReader.new.snippet_for(path, 99, 2).should be_nil
      end
    end

    it "returns nil for a file that does not exist" do
      NoirAIContext::SourceReader.new.snippet_for("/no/such/noir/file.rb", 1, 2).should be_nil
    end

    it "captures a radius-sized window around the line, 1-based and joined" do
      with_source_file("one\ntwo\nthree\nfour\nfive\n") do |path|
        NoirAIContext::SourceReader.new
          .snippet_for(path, 3, 1)
          .should eq("2: two | 3: three | 4: four")
      end
    end

    it "clamps the window at the start of the file" do
      with_source_file("one\ntwo\nthree\n") do |path|
        NoirAIContext::SourceReader.new
          .snippet_for(path, 1, 3)
          .should eq("1: one | 2: two | 3: three")
      end
    end

    it "clamps the window at the end of the file" do
      with_source_file("one\ntwo\nthree") do |path|
        NoirAIContext::SourceReader.new
          .snippet_for(path, 3, 3)
          .should eq("1: one | 2: two | 3: three")
      end
    end

    it "returns only the line itself at radius 0" do
      with_source_file("one\ntwo\nthree\n") do |path|
        NoirAIContext::SourceReader.new.snippet_for(path, 2, 0).should eq("2: two")
      end
    end

    # Blank lines used to emit bare `N: ` placeholders that spent the
    # character budget the surrounding code needs.
    it "drops blank lines instead of emitting bare line-number placeholders" do
      with_source_file("one\n\n\nfour\n") do |path|
        NoirAIContext::SourceReader.new
          .snippet_for(path, 1, 3)
          .should eq("1: one | 4: four")
      end
    end

    it "strips indentation and collapses interior whitespace runs" do
      with_source_file("    def    foo(a,   b)\n") do |path|
        NoirAIContext::SourceReader.new.snippet_for(path, 1, 0).should eq("1: def foo(a, b)")
      end
    end

    it "collapses a tab-indented line the same way" do
      with_source_file("\t\tres.json(x)\n") do |path|
        NoirAIContext::SourceReader.new.snippet_for(path, 1, 0).should eq("1: res.json(x)")
      end
    end

    it "returns nil when every line in the window is blank" do
      with_source_file("\n\n\n\n\n") do |path|
        NoirAIContext::SourceReader.new.snippet_for(path, 3, 1).should be_nil
      end
    end

    it "truncates the snippet at MAX_SNIPPET_CHARS" do
      long = ("x" * 300) + "\n"
      with_source_file(long) do |path|
        snippet = NoirAIContext::SourceReader.new.snippet_for(path, 1, 0)
        snippet.should_not be_nil
        snippet.not_nil!.size.should eq(NoirAIContext::SourceReader::MAX_SNIPPET_CHARS)
      end
    end

    it "leaves a snippet at exactly the budget untruncated" do
      body = "y" * (NoirAIContext::SourceReader::MAX_SNIPPET_CHARS - 3)
      with_source_file("#{body}\n") do |path|
        # "1: " + body == exactly MAX_SNIPPET_CHARS
        NoirAIContext::SourceReader.new.snippet_for(path, 1, 0).should eq("1: #{body}")
      end
    end

    it "serves a repeat request from the snippet cache" do
      with_source_file("one\ntwo\nthree\n") do |path|
        reader = NoirAIContext::SourceReader.new
        first = reader.snippet_for(path, 2, 0)
        File.write(path, "CHANGED\nCHANGED\nCHANGED\n")
        reader.snippet_for(path, 2, 0).should eq(first)
      end
    end

    it "keeps snippets for different radii separate in the cache" do
      with_source_file("one\ntwo\nthree\n") do |path|
        reader = NoirAIContext::SourceReader.new
        reader.snippet_for(path, 2, 0).should eq("2: two")
        reader.snippet_for(path, 2, 1).should eq("1: one | 2: two | 3: three")
      end
    end
  end

  describe "#route_scope_snippet_for" do
    it "returns nil without a path" do
      NoirAIContext::SourceReader.new.route_scope_snippet_for(nil, 1).should be_nil
    end

    it "returns nil for a line number below 1" do
      with_source_file("a\n") do |path|
        NoirAIContext::SourceReader.new.route_scope_snippet_for(path, 0).should be_nil
      end
    end

    it "returns nil for a line past the end of the file" do
      with_source_file("a\n") do |path|
        NoirAIContext::SourceReader.new.route_scope_snippet_for(path, 42).should be_nil
      end
    end

    it "returns nil for a file that does not exist" do
      NoirAIContext::SourceReader.new.route_scope_snippet_for("/no/such/noir/file.js", 1).should be_nil
    end

    context "brace-delimited handlers" do
      it "captures the handler body until the braces close" do
        source = <<-JS
          app.get('/users', (req, res) => {
            res.json(users)
          })
          app.get('/other', otherHandler)
          JS

        with_source_file(source, ".js") do |path|
          NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 1)
            .should eq("1: app.get('/users', (req, res) => { | 2: res.json(users) | 3: })")
        end
      end

      # Braces inside string literals are masked before the depth count,
      # so a `'}'` in the body must not close the block early.
      it "ignores braces inside string literals when tracking depth" do
        source = <<-JS
          app.get('/a', (req, res) => {
            res.send('}')
            res.end()
          })
          JS

        with_source_file(source, ".js") do |path|
          snippet = NoirAIContext::SourceReader.new.route_scope_snippet_for(path, 1)
          snippet.not_nil!.should contain("3: res.end()")
          snippet.not_nil!.should contain("4: })")
        end
      end

      it "does not bleed into the next handler" do
        source = <<-JS
          app.get('/a', (req, res) => {
            res.json(a)
          })
          app.post('/b', (req, res) => {
            res.json(b)
          })
          JS

        with_source_file(source, ".js") do |path|
          NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 1)
            .not_nil!.should_not contain("app.post")
        end
      end

      it "skips blank lines inside the body without ending the block" do
        source = <<-JS
          app.get('/a', (req, res) => {

            res.json(a)
          })
          JS

        with_source_file(source, ".js") do |path|
          NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 1)
            .should eq("1: app.get('/a', (req, res) => { | 3: res.json(a) | 4: })")
        end
      end
    end

    context "python-style handlers" do
      it "stops when indentation returns to the def column" do
        source = <<-PY
          @app.route("/x")
          def handler():
              return "ok"

          def other():
              return "no"
          PY

        with_source_file(source, ".py") do |path|
          NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 2)
            .should eq(%(1: @app.route("/x") | 2: def handler(): | 3: return "ok"))
        end
      end

      # The django `/public/` false positive: the *next* handler's
      # `@login_required` was captured into the previous handler's scope.
      it "does not capture the next function's decorator" do
        source = <<-PY
          def public_view(request):
              return render(request)

          @login_required
          def private_view(request):
              return render(request)
          PY

        with_source_file(source, ".py") do |path|
          NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 1)
            .not_nil!.should_not contain("login_required")
        end
      end

      it "captures decorator lines above the def" do
        source = <<-PY
          @csrf_exempt
          @app.route("/x")
          def handler():
              pass
          PY

        with_source_file(source, ".py") do |path|
          NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 3)
            .not_nil!.should contain("1: @csrf_exempt")
        end
      end

      it "looks back at most MAX_LEAD_DECORATOR_LINES decorator lines" do
        source = <<-PY
          @a
          @b
          @c
          @d
          @e
          def handler():
              pass
          PY

        with_source_file(source, ".py") do |path|
          snippet = NoirAIContext::SourceReader.new.route_scope_snippet_for(path, 6).not_nil!
          snippet.should contain("2: @b")
          snippet.should_not contain("1: @a")
        end
      end

      it "continues the lead-in scan past a blank line without emitting it" do
        source = <<-PY
          @app.route("/x")

          def handler():
              pass
          PY

        with_source_file(source, ".py") do |path|
          snippet = NoirAIContext::SourceReader.new.route_scope_snippet_for(path, 3).not_nil!
          snippet.should contain(%(1: @app.route("/x")))
          snippet.should_not contain("2: ")
        end
      end

      it "stops the lead-in scan at the first non-decorator line" do
        source = <<-PY
          CONSTANT = 1
          def handler():
              pass
          PY

        with_source_file(source, ".py") do |path|
          NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 2)
            .not_nil!.should_not contain("CONSTANT")
        end
      end
    end

    context "ruby-style handlers" do
      it "stops after the matching end at the def's indent" do
        source = <<-RB
          def index
            render json: @users
          end

          def show
            render json: @user
          end
          RB

        with_source_file(source, ".rb") do |path|
          NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 1)
            .should eq("1: def index | 2: render json: @users | 3: end")
        end
      end

      it "keeps a nested end without ending the block early" do
        source = <<-RB
          def index
            if admin?
              render json: @users
            end
            head :ok
          end
          RB

        with_source_file(source, ".rb") do |path|
          NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 1)
            .not_nil!.should contain("5: head :ok")
        end
      end
    end

    context "single-statement routes" do
      it "stops at the end of a one-line statement" do
        source = <<-JS
          app.get('/users', listUsers);
          app.get('/other', otherHandler);
          JS

        with_source_file(source, ".js") do |path|
          NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 1)
            .should eq("1: app.get('/users', listUsers);")
        end
      end

      it "keeps reading while parentheses are still open" do
        source = <<-GO
          r.HandleFunc("/users",
              listUsers)
          r.HandleFunc("/other", otherHandler)
          GO

        with_source_file(source, ".go") do |path|
          NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 1)
            .should eq(%(1: r.HandleFunc("/users", | 2: listUsers)))
        end
      end
    end

    context "budgets" do
      it "honours a caller-supplied max_lines" do
        source = <<-JS
          app.get('/a', (req, res) => {
            one()
            two()
            three()
            four()
          })
          JS

        with_source_file(source, ".js") do |path|
          snippet = NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 1, max_lines: 3).not_nil!
          snippet.should contain("3: two()")
          snippet.should_not contain("4: three()")
        end
      end

      it "caps the capture at MAX_ROUTE_SCOPE_LINES by default" do
        body = (1..40).map { |i| "  call#{i}()" }.join("\n")
        source = "app.get('/a', (req, res) => {\n#{body}\n})"

        with_source_file(source, ".js") do |path|
          snippet = NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 1, max_chars: 100_000).not_nil!
          snippet.should contain("call11()")
          snippet.should_not contain("call12()")
        end
      end

      it "honours a caller-supplied max_chars" do
        source = <<-JS
          app.get('/a', (req, res) => {
            res.json(payload)
          })
          JS

        with_source_file(source, ".js") do |path|
          NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 1, max_chars: 12)
            .not_nil!.size.should eq(12)
        end
      end

      it "truncates at MAX_SNIPPET_CHARS by default" do
        body = (1..20).map { |i| "  someCall#{i}(withArguments, andMore)" }.join("\n")
        source = "app.get('/a', (req, res) => {\n#{body}\n})"

        with_source_file(source, ".js") do |path|
          NoirAIContext::SourceReader.new
            .route_scope_snippet_for(path, 1)
            .not_nil!.size.should eq(NoirAIContext::SourceReader::MAX_SNIPPET_CHARS)
        end
      end
    end

    it "serves a repeat request from the route-scope cache" do
      with_source_file("app.get('/a', h);\n", ".js") do |path|
        reader = NoirAIContext::SourceReader.new
        first = reader.route_scope_snippet_for(path, 1)
        File.write(path, "app.get('/CHANGED', h);\n")
        reader.route_scope_snippet_for(path, 1).should eq(first)
      end
    end

    it "keeps entries for different budgets separate in the cache" do
      source = <<-JS
        app.get('/a', (req, res) => {
          res.json(payload)
        })
        JS

      with_source_file(source, ".js") do |path|
        reader = NoirAIContext::SourceReader.new
        wide = reader.route_scope_snippet_for(path, 1, max_chars: 1000)
        narrow = reader.route_scope_snippet_for(path, 1, max_chars: 10)
        narrow.not_nil!.size.should eq(10)
        wide.not_nil!.size.should be > 10
      end
    end
  end

  describe "#lines_for" do
    it "returns an empty array without a path" do
      NoirAIContext::SourceReader.new.lines_for(nil).should eq([] of String)
    end

    it "returns an empty array for a file that does not exist" do
      NoirAIContext::SourceReader.new.lines_for("/no/such/noir/file.rb").should eq([] of String)
    end

    it "splits the file into lines" do
      with_source_file("one\ntwo\nthree") do |path|
        NoirAIContext::SourceReader.new.lines_for(path).should eq(["one", "two", "three"])
      end
    end

    it "keeps the trailing empty element for a file ending in a newline" do
      with_source_file("one\ntwo\n") do |path|
        NoirAIContext::SourceReader.new.lines_for(path).should eq(["one", "two", ""])
      end
    end

    it "serves a repeat read from the file cache" do
      with_source_file("one\ntwo\n") do |path|
        reader = NoirAIContext::SourceReader.new
        first = reader.lines_for(path)
        File.write(path, "CHANGED\n")
        reader.lines_for(path).should eq(first)
      end
    end

    # `lines_for` hands back the cached array itself rather than a copy —
    # a documented contract the augmentor's hot path depends on.
    it "returns the same array instance on a cache hit" do
      with_source_file("one\ntwo\n") do |path|
        reader = NoirAIContext::SourceReader.new
        reader.lines_for(path).same?(reader.lines_for(path)).should be_true
      end
    end
  end
end
