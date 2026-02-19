require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/llm_analyzers/unified_ai"
require "file_utils"

class Analyzer::AI::Unified
  def __test_agentic_enabled : Bool
    @use_agentic
  end

  def __test_run_agent_tool(action : String, args_json : String) : String
    run_agent_tool(action, JSON.parse(args_json))
  end

  def __test_parse_agent_action(payload : String)
    parse_agent_action(payload)
  end

  def __test_append_agent_message(messages : Array(Hash(String, String)), role : String, content : String)
    append_agent_message(messages, role, content)
  end

  def __test_agent_context_limits : {Int32, Int32}
    {AGENT_CONTEXT_MAX_DYNAMIC_MESSAGES, AGENT_CONTEXT_MAX_CHARS}
  end

  def __test_estimate_messages_chars(messages : Array(Hash(String, String))) : Int32
    estimate_messages_chars(messages)
  end

  def __test_agent_tool_cache_size : Int32
    @agent_tool_cache.size
  end

  def __test_agent_tool_result_char_limit : Int32
    AGENT_TOOL_RESULT_MAX_CHARS
  end

  def __test_compact_tool_result(result : String) : String
    compact_tool_result(result)
  end
end

private def build_ai_options(base_dir : String, ai_agent : Bool = true) : Hash(String, YAML::Any)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(base_dir)])
  options["ai_provider"] = YAML::Any.new("openai")
  options["ai_model"] = YAML::Any.new("gpt-4o-mini")
  options["ai_agent"] = YAML::Any.new(ai_agent)
  options["ai_max_token"] = YAML::Any.new(1024)
  options
end

describe Analyzer::AI::Unified do
  describe "agentic helpers" do
    it "enables agentic mode from option" do
      options = build_ai_options(".", true)
      analyzer = Analyzer::AI::Unified.new(options)
      analyzer.__test_agentic_enabled.should be_true
    end

    it "blocks read_file for paths outside base path" do
      temp_dir = File.tempname
      outside_file = File.tempname
      Dir.mkdir(temp_dir)
      begin
        File.write(outside_file, "outside")
        analyzer = Analyzer::AI::Unified.new(build_ai_options(temp_dir))
        result = analyzer.__test_run_agent_tool("read_file", %({"path":"#{outside_file}"}))
        result.should contain("outside base paths")
      ensure
        FileUtils.rm_rf(temp_dir)
        File.delete(outside_file) if File.exists?(outside_file)
      end
    end

    it "truncates large files in read_file tool" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        File.write(File.join(temp_dir, "large.cr"), "A" * 12_000)
        analyzer = Analyzer::AI::Unified.new(build_ai_options(temp_dir))
        result = analyzer.__test_run_agent_tool("read_file", %({"path":"large.cr"}))
        result.should contain("truncated large file")
        result.should contain("---HEAD---")
        result.should contain("---TAIL---")
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "returns grep matches for in-scope files" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        File.write(File.join(temp_dir, "routes.cr"), "get \"/health\" do\nend\n")
        analyzer = Analyzer::AI::Unified.new(build_ai_options(temp_dir))
        result = analyzer.__test_run_agent_tool("grep", %({"pattern":"health","path":".","file_pattern":"*.cr"}))
        result.should contain("routes.cr:1:")
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "caches repeated tool calls for identical inputs" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        File.write(File.join(temp_dir, "routes.cr"), "get \"/health\" do\nend\n")
        analyzer = Analyzer::AI::Unified.new(build_ai_options(temp_dir))

        analyzer.__test_agent_tool_cache_size.should eq(0)
        first = analyzer.__test_run_agent_tool("grep", %({"pattern":"health","path":".","file_pattern":"*.cr"}))
        size_after_first = analyzer.__test_agent_tool_cache_size
        second = analyzer.__test_run_agent_tool("grep", %({"pattern":"health","path":".","file_pattern":"*.cr"}))
        size_after_second = analyzer.__test_agent_tool_cache_size

        first.should eq(second)
        size_after_first.should eq(1)
        size_after_second.should eq(size_after_first)
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "parses action payload shape" do
      analyzer = Analyzer::AI::Unified.new(build_ai_options("."))
      action = analyzer.__test_parse_agent_action(%({"action":"grep","args":{"pattern":"route"}}))
      action.should_not be_nil

      if action
        action[:action].should eq("grep")
        action[:args]["pattern"].as_s.should eq("route")
      end
    end

    it "prunes agent context growth by message count and char budget" do
      analyzer = Analyzer::AI::Unified.new(build_ai_options("."))
      messages = [
        {"role" => "system", "content" => "system"},
        {"role" => "user", "content" => "seed"},
      ] of Hash(String, String)

      30.times do |i|
        analyzer.__test_append_agent_message(messages, "assistant", %({"action":"grep","args":{"pattern":"p#{i}"}}))
        analyzer.__test_append_agent_message(messages, "user", "Tool result:\n" + ("x" * 12_000))
      end

      dynamic_limit, char_limit = analyzer.__test_agent_context_limits
      (messages.size - 2).should be <= dynamic_limit
      analyzer.__test_estimate_messages_chars(messages).should be <= char_limit
      messages[0]["role"].should eq("system")
      messages[1]["role"].should eq("user")
    end

    it "compacts oversized tool results before feedback append" do
      analyzer = Analyzer::AI::Unified.new(build_ai_options("."))
      limit = analyzer.__test_agent_tool_result_char_limit
      compacted = analyzer.__test_compact_tool_result("x" * (limit + 4000))

      compacted.should contain("tool result truncated")
      compacted.should contain("---HEAD---")
      compacted.should contain("---TAIL---")
      compacted.size.should be < limit + 512
    end
  end
end
