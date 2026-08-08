require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/llm_analyzers/unified_ai"
require "file_utils"

module LLM
  # Mocking get_max_tokens for testing purposes
  def self.get_max_tokens(provider_url : String, model_name : String)
    # Allow dynamic mock behavior if needed, otherwise return a default
    @@mock_max_tokens_value || 1024 # Default mock value
  end

  # Helper to set the mock return value for get_max_tokens
  def self.mock_max_tokens=(value : Int32)
    @@mock_max_tokens_value = value
  end

  def self.reset_mock_max_tokens
    @@mock_max_tokens_value = nil
  end
end

describe Analyzer::AI::Unified do
  before_each do
    LLM.reset_mock_max_tokens
  end

  describe "#initialize" do
    it "uses ai_max_token from options if provided with ai_provider" do
      options = Hash{
        "url"          => YAML::Any.new(""),
        "debug"        => YAML::Any.new(false),
        "verbose"      => YAML::Any.new(false),
        "color"        => YAML::Any.new(false),
        "nolog"        => YAML::Any.new(false),
        "ai_provider"  => YAML::Any.new("http://localhost:8000"),
        "ai_model"     => YAML::Any.new("test-model"),
        "ai_key"       => YAML::Any.new("test-key"),
        "ai_max_token" => YAML::Any.new(2048),
        "base"         => YAML::Any.new([YAML::Any.new(".")]),
      }
      analyzer = Analyzer::AI::Unified.new(options)
      analyzer.max_tokens.should eq(2048)
    end

    it "uses LLM.get_max_tokens if ai_max_token is not provided" do
      options = Hash{
        "url"         => YAML::Any.new(""),
        "debug"       => YAML::Any.new(false),
        "verbose"     => YAML::Any.new(false),
        "color"       => YAML::Any.new(false),
        "nolog"       => YAML::Any.new(false),
        "ai_provider" => YAML::Any.new("http://localhost:8000"),
        "ai_model"    => YAML::Any.new("test-model"),
        "ai_key"      => YAML::Any.new("test-key"),
        "base"        => YAML::Any.new([YAML::Any.new(".")]),
      }
      analyzer = Analyzer::AI::Unified.new(options)
      analyzer.max_tokens.should eq(1024)
    end

    it "allows acp provider without ai_model" do
      options = Hash{
        "url"         => YAML::Any.new(""),
        "debug"       => YAML::Any.new(false),
        "verbose"     => YAML::Any.new(false),
        "color"       => YAML::Any.new(false),
        "nolog"       => YAML::Any.new(false),
        "ai_provider" => YAML::Any.new("acp:codex"),
        "ai_model"    => YAML::Any.new(""),
        "ai_key"      => YAML::Any.new(""),
        "base"        => YAML::Any.new([YAML::Any.new(".")]),
      }
      analyzer = Analyzer::AI::Unified.new(options)
      analyzer.max_tokens.should eq(1024)
    end
  end

  # The agent's file tools (read_file, list_directory, grep) take paths the
  # LLM picked, and the LLM is steered by the source tree being scanned.
  # Anything that escapes the scan base gets read and shipped to the provider.
  describe "#path_within_base?" do
    it "confines agent file tools to the scan base, symlinks included" do
      root = File.tempname("noir-agent-base")
      outside = File.tempname("noir-agent-outside")
      begin
        Dir.mkdir_p(File.join(root, "src", "nested"))
        Dir.mkdir_p(outside)
        File.write(File.join(root, "src", "app.rb"), "get '/' do; end\n")
        File.write(File.join(outside, "id_rsa"), "PRIVATE KEY\n")

        # What a hostile checkout can plant: a link to a file, and a link to
        # a whole directory, both sitting innocently inside the repo.
        File.symlink(File.join(outside, "id_rsa"), File.join(root, "src", "notes.rb"))
        File.symlink(outside, File.join(root, "vendor"))

        options = Hash{
          "url"         => YAML::Any.new(""),
          "debug"       => YAML::Any.new(false),
          "verbose"     => YAML::Any.new(false),
          "color"       => YAML::Any.new(false),
          "nolog"       => YAML::Any.new(false),
          "ai_provider" => YAML::Any.new("http://localhost:8000"),
          "ai_model"    => YAML::Any.new("test-model"),
          "ai_key"      => YAML::Any.new(""),
          "base"        => YAML::Any.new([YAML::Any.new(root)]),
        }
        analyzer = Analyzer::AI::Unified.new(options)

        analyzer.path_within_base?(File.join(root, "src", "app.rb")).should be_true
        analyzer.path_within_base?(File.join(root, "src", "nested")).should be_true
        analyzer.path_within_base?(root).should be_true

        # Lexical escape.
        analyzer.path_within_base?(File.join(root, "..", "etc", "passwd")).should be_false
        analyzer.path_within_base?(File.join(outside, "id_rsa")).should be_false
        # Symlinked file: passes a purely lexical prefix check, must not pass.
        analyzer.path_within_base?(File.join(root, "src", "notes.rb")).should be_false
        # Symlinked directory, and a path reached through one.
        analyzer.path_within_base?(File.join(root, "vendor")).should be_false
        analyzer.path_within_base?(File.join(root, "vendor", "id_rsa")).should be_false
      ensure
        FileUtils.rm_rf(root)
        FileUtils.rm_rf(outside)
      end
    end
  end
end
