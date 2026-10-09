require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/llm_analyzers/unified_ai"
require "http/server"

# Records every chat-completions body it is sent.
private class BodyRecorder
  getter bodies = [] of String

  def initialize
    @server = HTTP::Server.new do |context|
      @bodies << (context.request.body.try(&.gets_to_end) || "")
      context.response.content_type = "application/json"
      context.response.print({choices: [{message: {content: %({"endpoints":[]})}}]}.to_json)
    end
    @address = @server.bind_tcp("127.0.0.1", 0)
    spawn { @server.listen }
    Fiber.yield
  end

  def url : String
    "http://127.0.0.1:#{@address.port}/v1"
  end

  def close
    @server.close
  end
end

describe Analyzer::AI::Unified do
  # A project of five files or fewer took the per-file path, which sends each
  # file whole: one 1 MB file went out as a single 1 MB request whatever
  # --ai-max-token said.
  it "keeps a small project with one oversized file within --ai-max-token" do
    server = BodyRecorder.new
    root = File.tempname("noir-ai-budget")
    prev_disable = ENV["NOIR_CACHE_DISABLE"]?
    prev_prompt = LLM::PromptOverrides.analyze_prompt
    ENV["NOIR_CACHE_DISABLE"] = "1"
    LLM::PromptOverrides.analyze_prompt = "CUSTOM-ANALYZE-PROMPT"
    begin
      Dir.mkdir_p(root)
      big = File.join(root, "routes.js")
      small = File.join(root, "small.js")
      File.write(big, (0...2000).map { |i| "app.get('/r#{i}', handler)\n" }.join)
      File.write(small, "app.get('/small', handler)\n")
      CodeLocator.instance.reset_files
      CodeLocator.instance.register_path(big)
      CodeLocator.instance.register_path(small)

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(root)])
      options["ai_provider"] = YAML::Any.new(server.url)
      options["ai_model"] = YAML::Any.new("test-model")
      options["ai_max_token"] = YAML::Any.new(4000)
      Analyzer::AI::Unified.new(options).analyze

      server.bodies.size.should be > 2
      # 4000 tokens at the ~4 chars/token the bundler budgets with, plus
      # the JSON envelope and the response format schema.
      server.bodies.max_of(&.bytesize).should be < 4000 * 4 + 4096
      # Only the oversized file is bundled; the small one keeps the
      # per-file prompt the user overrode.
      overridden = server.bodies.select(&.includes?("CUSTOM-ANALYZE-PROMPT"))
      overridden.size.should eq(1)
      overridden[0].should contain("/small")
    ensure
      LLM::PromptOverrides.analyze_prompt = prev_prompt
      CodeLocator.instance.reset_files
      FileUtils.rm_rf(root)
      server.close
      prev_disable ? (ENV["NOIR_CACHE_DISABLE"] = prev_disable) : ENV.delete("NOIR_CACHE_DISABLE")
    end
  end
end
