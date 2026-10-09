require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/llm_analyzers/unified_ai"
require "http/server"

# Records the size of every chat-completions body it is sent.
private class BodySizeRecorder
  getter sizes = [] of Int32

  def initialize
    @server = HTTP::Server.new do |context|
      @sizes << (context.request.body.try(&.gets_to_end) || "").bytesize
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
    server = BodySizeRecorder.new
    root = File.tempname("noir-ai-budget")
    prev_disable = ENV["NOIR_CACHE_DISABLE"]?
    ENV["NOIR_CACHE_DISABLE"] = "1"
    begin
      Dir.mkdir_p(root)
      path = File.join(root, "routes.js")
      File.write(path, (0...2000).map { |i| "app.get('/r#{i}', handler)\n" }.join)
      CodeLocator.instance.reset_files
      CodeLocator.instance.register_path(path)

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(root)])
      options["ai_provider"] = YAML::Any.new(server.url)
      options["ai_model"] = YAML::Any.new("test-model")
      options["ai_max_token"] = YAML::Any.new(4000)
      Analyzer::AI::Unified.new(options).analyze

      server.sizes.size.should be > 1
      # 4000 tokens at the ~4 chars/token the bundler budgets with, plus
      # the JSON envelope and the response format schema.
      server.sizes.max.should be < 4000 * 4 + 4096
    ensure
      CodeLocator.instance.reset_files
      FileUtils.rm_rf(root)
      server.close
      prev_disable ? (ENV["NOIR_CACHE_DISABLE"] = prev_disable) : ENV.delete("NOIR_CACHE_DISABLE")
    end
  end
end
