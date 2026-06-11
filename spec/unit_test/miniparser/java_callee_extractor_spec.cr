require "../../spec_helper"
require "../../../src/miniparsers/java_callee_extractor"

# Convenience: parse Java source and yield the root so each spec can
# focus on the assertion. The tree-sitter root is GC-rooted by the
# closure for the duration of the block.
private def with_java_root(source : String, &)
  Noir::TreeSitter.parse_java(source) do |root|
    yield root
  end
end

describe Noir::JavaCalleeExtractor do
  describe ".callees_in_method" do
    it "captures unqualified, qualified, this-, and static-receiver calls inside the method body" do
      source = <<-JAVA
        package app;
        class UserController {
          public String show(Long id) {
            User user = service.findById(id);
            this.validate(user);
            return Renderer.html(user);
          }
          public void validate(User u) {}
        }
        JAVA

      callees = [] of Tuple(String, String, Int32)
      with_java_root(source) do |root|
        callees = Noir::JavaCalleeExtractor.callees_in_method(
          root, source, "UserController.java", "UserController", "show"
        )
      end
      names = callees.map(&.[0])
      names.should contain("service.findById")
      names.should contain("this.validate")
      names.should contain("Renderer.html")
      # Every emitted callee should report the right file path so the
      # AI-context surface can deep-link back into source.
      callees.each(&.[1].should(eq("UserController.java")))
    end

    it "captures Java method references as dotted callees" do
      source = <<-JAVA
        package app;
        class QueueResource {
          public List<Quark> receive() {
            return messages.stream()
              .map(Message::body)
              .map(this::toQuark)
              .map(FileObject::from)
              .collect(Collectors.toList());
          }
          private Quark toQuark(String message) {
            return parse(message);
          }
          private Quark parse(String message) { return null; }
        }
        JAVA

      to_quark_line = source.lines.index!(&.includes?("private Quark toQuark")) + 1
      callees = [] of Tuple(String, String, Int32)
      with_java_root(source) do |root|
        callees = Noir::JavaCalleeExtractor.callees_in_method(
          root, source, "QueueResource.java", "QueueResource", "receive"
        )
      end

      names = callees.map(&.[0])
      names.should contain("Message.body")
      names.should contain("this.toQuark")
      names.should contain("FileObject.from")
      names.should contain("Collectors.toList")

      local_ref = callees.find { |entry| entry[0] == "this.toQuark" }
      local_ref.should_not be_nil
      local_ref.not_nil![2].should eq(to_quark_line)
    end

    it "returns an empty list when the class or method can't be found" do
      source = <<-JAVA
        package app;
        class A { public void m() {} }
        JAVA

      callees = nil
      with_java_root(source) do |root|
        callees = Noir::JavaCalleeExtractor.callees_in_method(root, source, "A.java", "MissingClass", "m")
      end
      callees.not_nil!.should be_empty

      with_java_root(source) do |root|
        callees = Noir::JavaCalleeExtractor.callees_in_method(root, source, "A.java", "A", "missingMethod")
      end
      callees.not_nil!.should be_empty
    end

    it "guards against empty class_name or method_name without raising" do
      source = "class A { public void m() {} }"
      with_java_root(source) do |root|
        Noir::JavaCalleeExtractor.callees_in_method(root, source, "A.java", "", "m").should be_empty
        Noir::JavaCalleeExtractor.callees_in_method(root, source, "A.java", "A", "").should be_empty
      end
    end

    it "drops chained-on-call receivers (filter().first → noisy duplicate)" do
      source = <<-JAVA
        class Repo {
          public User show() {
            return query().first();
          }
        }
        JAVA

      callees = nil
      with_java_root(source) do |root|
        callees = Noir::JavaCalleeExtractor.callees_in_method(root, source, "Repo.java", "Repo", "show")
      end
      names = callees.not_nil!.map(&.[0])

      names.should contain("query")
      # `query().first` would surface as a noisy duplicate with the
      # inner call already counted; the chained-on-call filter drops
      # it deliberately.
      names.should_not contain("query.first")
      names.any?(&.includes?("()")).should be_false
    end

    it "resolves unqualified calls and this.calls to the same-file declaration line" do
      source = <<-JAVA
        class Controller {
          public void entry() {
            helper();
            this.helper();
            External.run();
          }
          public void helper() {}
        }
        JAVA

      callees = nil
      with_java_root(source) do |root|
        callees = Noir::JavaCalleeExtractor.callees_in_method(root, source, "Controller.java", "Controller", "entry")
      end
      arr = callees.not_nil!

      # `helper()` line in source — `public void helper() {}` is row 6
      # (0-based), so 1-based line is 7. Both unqualified and `this.`
      # qualified calls resolve to that line.
      helper_calls = arr.select { |t| t[0] == "helper" || t[0] == "this.helper" }
      helper_calls.size.should eq(2)
      helper_calls.each do |c|
        c[2].should eq(7)
      end

      # Static-qualified call should NOT resolve — it points at the
      # call site instead so reviewers see the invocation, not the
      # (likely non-existent) external definition.
      ext = arr.find { |t| t[0] == "External.run" }
      ext.should_not be_nil
      ext.not_nil![2].should_not eq(7)
    end

    it "leaves ambiguous (overloaded) names at the call site" do
      source = <<-JAVA
        class Service {
          public void entry() {
            handle("x");
          }
          public void handle(String s) {}
          public void handle(int n) {}
        }
        JAVA

      callees = nil
      with_java_root(source) do |root|
        callees = Noir::JavaCalleeExtractor.callees_in_method(root, source, "Service.java", "Service", "entry")
      end
      handle = callees.not_nil!.find { |t| t[0] == "handle" }
      handle.should_not be_nil
      # Ambiguous → caller falls back to the call-site row (row 2
      # within source, 1-based line 3) rather than guessing which
      # overload to point at.
      handle.not_nil![2].should eq(3)
    end

    it "uses target_line to pick the right overloaded handler body" do
      source = <<-JAVA
        package app;
        class VisitResource {
          public List<Visit> read(int petId) {
            return repo.findByPetId(petId);
          }
          public Visits read(List<Integer> petIds) {
            return repo.findByPetIdIn(petIds);
          }
        }
        JAVA

      # The second `read` spans rows 5-7 (0-based); pointing at row 5
      # must resolve callees from that overload, not the first `read`.
      with_target = [] of Tuple(String, String, Int32)
      without_target = [] of Tuple(String, String, Int32)
      with_java_root(source) do |root|
        with_target = Noir::JavaCalleeExtractor.callees_in_method(
          root, source, "VisitResource.java", "VisitResource", "read", 5
        )
        without_target = Noir::JavaCalleeExtractor.callees_in_method(
          root, source, "VisitResource.java", "VisitResource", "read"
        )
      end
      with_target.map(&.[0]).should eq(["repo.findByPetIdIn"])
      # No hint → first overload.
      without_target.map(&.[0]).should eq(["repo.findByPetId"])
    end
  end

  describe ".callees_in_body" do
    it "walks an arbitrary body node and emits each method_invocation" do
      source = <<-JAVA
        class C {
          public void m() {
            a();
            b.c();
            xs.stream().map(Type::from);
          }
        }
        JAVA

      callees = nil
      with_java_root(source) do |root|
        # Re-locate the method's body the way an analyzer would.
        Noir::TreeSitter.each_named_child(root) do |class_decl|
          next unless Noir::TreeSitter.node_type(class_decl) == "class_declaration"
          body = Noir::TreeSitter.field(class_decl, "body")
          next unless body
          Noir::TreeSitter.each_named_child(body) do |member|
            next unless Noir::TreeSitter.node_type(member) == "method_declaration"
            method_body = Noir::TreeSitter.field(member, "body")
            next unless method_body
            callees = Noir::JavaCalleeExtractor.callees_in_body(method_body, source, "C.java")
          end
        end
      end

      names = callees.not_nil!.map(&.[0])
      names.should contain("a")
      names.should contain("b.c")
      names.should contain("Type.from")
    end
  end
end
