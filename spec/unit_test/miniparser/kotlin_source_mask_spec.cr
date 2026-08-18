require "spec"
require "../../../src/miniparsers/kotlin_source_mask"

describe Noir::KotlinSourceMask do
  it "preserves the character count of a non-ASCII comment" do
    # One space per *character*, not per byte. `String#[]` and
    # `MatchData#begin/#end` are char-indexed, so a byte-per-space mask
    # shifted every offset after a multi-byte comment and callers slicing
    # the raw line with an offset taken on the mask over-trimmed it.
    source = %(/* 조건 */ fun handler() = path("/mcp"))
    masked = Noir::KotlinSourceMask.visible(source)

    masked.size.should eq(source.size)
    # `/* 조건 */` is 8 characters, plus the space before `fun`.
    masked.should eq("#{" " * 9}fun handler() = path(#{" " * 6})")
  end

  it "preserves the character count of a non-ASCII string literal" do
    source = %(val label = "설정 화면" // 주석)
    Noir::KotlinSourceMask.visible(source).size.should eq(source.size)
    Noir::KotlinSourceMask.code_only(source).size.should eq(source.size)
  end

  it "keeps line offsets and count for every line" do
    source = <<-KT
      // 한국어 주석
      const val PATH = "/mcp"
      /* 여러 줄
         주석 */
      val other = "값"
      KT

    source.lines.zip(Noir::KotlinSourceMask.visible(source).lines) do |raw, masked|
      masked.size.should eq(raw.size)
    end
    source.lines.zip(Noir::KotlinSourceMask.code_only(source).lines) do |raw, masked|
      masked.size.should eq(raw.size)
    end
  end

  it "blanks comments but keeps string literals in code_only" do
    source = <<-KT
      // const val PATH = "/old"
      const val PATH = "/mcp" /* trailing */
      KT

    Noir::KotlinSourceMask.code_only(source).should eq(
      %(#{" " * 26}\nconst val PATH = "/mcp"#{" " * 15})
    )
  end

  it "blanks both comments and string contents in visible" do
    source = %(val path = "/a{b}" // {c})
    # `"/a{b}"` (7) + separator (1) + `// {c}` (6), all blanked.
    Noir::KotlinSourceMask.visible(source).should eq("val path =#{" " * 15}")
  end

  it "leaves a raw string's delimiters and body intact in code_only" do
    source = %(val q = """SELECT * FROM t WHERE a = "b"""" + x)
    Noir::KotlinSourceMask.code_only(source).should eq(source)
  end
end
