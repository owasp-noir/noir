require "../../spec_helper"
require "../../../src/ext/tree_sitter/tree_sitter"

private def has_error?(node : LibTreeSitter::TSNode) : Bool
  return true if Noir::TreeSitter.node_type(node) == "ERROR"
  Noir::TreeSitter.each_named_child(node) { |child| return true if has_error?(child) }
  false
end

describe "Noir::TreeSitter.parse_kotlin multi-dollar strings" do
  it "parses a class whose constructor uses a Kotlin 2.2 multi-dollar string" do
    source = <<-'KT'
      @RestController
      class SettingsController(
        @param:Value($$"${server.port:#{null}}") private val port: Int?,
        @param:Value($$$"""raw $${x} $$$name""") private val raw: String,
      ) {
        @GetMapping("/a/$ID") fun a() = "$$"
        @GetMapping("/b/${'$'}") fun b() = "${"$$\""}"
      }
      KT

    text = Noir::TreeSitter.kotlin_parse_text(source)
    text.bytesize.should eq(source.bytesize)
    text.should contain(%q(  "_{server.port:#{null}}"))
    text.should contain(%q(   """raw __{x} ___name"""))
    # A `$$` that closes an ordinary string, and templates, stay as written.
    text.should contain(%q("/a/$ID"))
    text.should contain(%q(= "$$"))
    text.should contain(%q("/b/${'$'}"))

    errors = true
    Noir::TreeSitter.parse_kotlin(source) { |root| errors = has_error?(root) }
    errors.should be_false
  end

  it "leaves sources without multi-dollar strings untouched" do
    source = %q(val a = "$x ${y}" // $$"\n)
    Noir::TreeSitter.kotlin_parse_text(source).should eq(source)
  end
end
