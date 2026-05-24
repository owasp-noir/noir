require "../../spec_helper"
require "../../../src/miniparsers/python_callee_extractor"

describe Noir::PythonCalleeExtractor do
  it "extracts identifier-form callees from a function body" do
    source = <<-PY
      def show(id):
          user = lookup_user(id)
          record_audit(user)
          return present(user)
      PY

    names = Noir::PythonCalleeExtractor.calls_in(source).map(&.first)
    names.should contain("lookup_user")
    names.should contain("record_audit")
    names.should contain("present")
  end

  it "extracts dotted attribute callees (a.b)" do
    source = <<-PY
      def handler():
          user = User.find(1)
          flash.error("oops")
          return render(user)
      PY

    names = Noir::PythonCalleeExtractor.calls_in(source).map(&.first)
    names.should contain("User.find")
    names.should contain("flash.error")
    names.should contain("render")
  end

  it "joins multi-segment attribute chains rooted on identifiers" do
    source = <<-PY
      def handler():
          return audit.log.write("show")
      PY

    names = Noir::PythonCalleeExtractor.calls_in(source).map(&.first)
    names.should contain("audit.log.write")
  end

  it "filters out builtins so they don't crowd the callee list" do
    source = <<-PY
      def handler(items):
          print(items)
          n = len(items)
          sorted_items = sorted(items)
          return jsonify(sorted_items)
      PY

    names = Noir::PythonCalleeExtractor.calls_in(source).map(&.first)
    # Builtins must be dropped …
    names.should_not contain("print")
    names.should_not contain("len")
    names.should_not contain("sorted")
    # … while framework-specific helpers like jsonify must survive.
    names.should contain("jsonify")
  end

  it "drops bare-identifier dunder calls (__import__ / __subclasshook__)" do
    source = <<-PY
      def handler():
          __import__("os")
          return user_lookup()
      PY

    # The dunder filter applies to identifier-form callees only.
    # Attribute-form dunders (e.g. `o.__init__()`) reach the callee
    # list because they're useful signal in some review contexts.
    names = Noir::PythonCalleeExtractor.calls_in(source).map(&.first)
    names.should_not contain("__import__")
    names.should contain("user_lookup")
  end

  it "drops chained attribute calls rooted on another call (User.query.filter(args).first)" do
    source = <<-PY
      def handler(args):
          return User.query.filter(args).first()
      PY

    names = Noir::PythonCalleeExtractor.calls_in(source).map(&.first)
    # Inner identifier-rooted call is captured …
    names.should contain("User.query.filter")
    # … but the outer .first() on the call result is dropped to avoid
    # the noisy duplicate that would carry argument text.
    names.should_not contain("filter(args).first")
    names.any?(&.includes?("(")).should be_false
  end

  it "reports 0-based rows relative to the source snippet" do
    source = <<-PY
      def handler():
          result = lookup_user()
          return present(result)
      PY

    rows = Noir::PythonCalleeExtractor.calls_in(source).to_h
    # `def handler():` is row 0, body lines start at row 1.
    rows["lookup_user"].should eq(1)
    rows["present"].should eq(2)
  end

  it "returns an empty list for an empty / no-call body" do
    Noir::PythonCalleeExtractor.calls_in("").should be_empty
    Noir::PythonCalleeExtractor.calls_in("def handler():\n    pass\n").should be_empty
  end
end
