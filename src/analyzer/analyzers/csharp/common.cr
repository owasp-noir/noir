require "../../../miniparsers/csharp_callee_extractor"

module Analyzer::CSharp::Common
  # Standard .NET test-source conventions:
  #
  #   * `/test/` and `/tests/` parent directories — Microsoft's
  #     own repos park unit + integration tests under
  #     `src/<Project>/test/...` (aspnetcore) or `tests/...`
  #     (smaller solutions).
  #   * `/testassets/` — aspnetcore's helper-controller convention
  #     for spinning up a real server inside the test harness.
  #   * `Tests.cs` / `Test.cs` filename — xUnit / NUnit / MSTest
  #     suffix convention.
  #
  # dotnet/aspnetcore alone parks ~3,600 phantom endpoints under
  # `src/Mvc/test/...` and similar trees. Production code never
  # adopts any of these.
  def self.csharp_test_path?(path : String) : Bool
    return true if path.includes?("/test/")
    return true if path.includes?("/tests/")
    return true if path.includes?("/testassets/")
    base = File.basename(path)
    return true if base.ends_with?("Tests.cs")
    base.ends_with?("Test.cs")
  end

  protected def build_signature(lines : Array(String), start_index : Int32) : Tuple(String, Int32)
    signature = lines[start_index]
    paren_count = signature.count('(') - signature.count(')')
    index = start_index + 1

    while paren_count > 0 && index < lines.size
      signature += " " + lines[index]
      paren_count += lines[index].count('(') - lines[index].count(')')
      index += 1
    end

    {signature, index - 1}
  end

  protected def split_csharp_parameters(param_list : String) : Array(String)
    params = [] of String
    current = String::Builder.new
    generic_depth = 0
    paren_depth = 0
    bracket_depth = 0

    param_list.each_char do |char|
      case char
      when '<'
        generic_depth += 1
      when '>'
        generic_depth -= 1 if generic_depth > 0
      when '('
        paren_depth += 1
      when ')'
        paren_depth -= 1 if paren_depth > 0
      when '['
        bracket_depth += 1
      when ']'
        bracket_depth -= 1 if bracket_depth > 0
      when ','
        if generic_depth == 0 && paren_depth == 0 && bracket_depth == 0
          params << current.to_s.strip
          current = String::Builder.new
          next
        end
      end

      current << char
    end

    tail = current.to_s.strip
    params << tail unless tail.empty?
    params
  end

  protected def extract_method_block(lines : Array(String), start_index : Int32) : String
    io = String::Builder.new
    brace = 0
    started = false
    index = start_index

    while index < lines.size
      line = lines[index]
      brace += line.count('{') - line.count('}')
      started ||= brace > 0 || line.includes?("{")
      io << line
      io << '\n'
      if started && brace <= 0 && line.includes?("}")
        break
      end
      index += 1
    end

    io.to_s
  end

  protected def attach_csharp_callees(endpoint : Endpoint,
                                      block : String,
                                      file : String,
                                      start_line : Int32,
                                      include_callee : Bool,
                                      *,
                                      skip_first_line : Bool = false)
    return unless include_callee

    callees = Noir::CSharpCalleeExtractor.callees_for_block(block, file, start_line, skip_first_line: skip_first_line)
    Noir::CSharpCalleeExtractor.attach_to(endpoint, callees)
  end
end
