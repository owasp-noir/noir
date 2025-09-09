require "spec"
require "yaml"

describe "Hidden Prompt Override Flag Extraction" do
  it "extracts override-filter-prompt flag correctly" do
    args = ["--override-filter-prompt", "Test filter prompt", "-b", "/tmp/test"]
    options = Hash(String, YAML::Any).new
    
    # Simulate the extract_hidden_prompt_flags function logic
    filtered_args = [] of String
    i = 0

    while i < args.size
      arg = args[i]
      case arg
      when "--override-filter-prompt"
        if i + 1 < args.size && !args[i + 1].starts_with?("-")
          options["override_filter_prompt"] = YAML::Any.new(args[i + 1])
          i += 2
        end
      else
        filtered_args << arg
        i += 1
      end
    end

    options.has_key?("override_filter_prompt").should be_true
    options["override_filter_prompt"].to_s.should eq("Test filter prompt")
    filtered_args.should eq(["-b", "/tmp/test"])
  end

  it "extracts all four prompt override flags" do
    args = [
      "--override-filter-prompt", "Custom filter",
      "--override-analyze-prompt", "Custom analyze",
      "--override-bundle-analyze-prompt", "Custom bundle",
      "--override-llm-optimize-prompt", "Custom optimize",
      "-b", "/tmp/test"
    ]
    options = Hash(String, YAML::Any).new
    
    filtered_args = [] of String
    i = 0

    while i < args.size
      arg = args[i]
      case arg
      when "--override-filter-prompt"
        if i + 1 < args.size && !args[i + 1].starts_with?("-")
          options["override_filter_prompt"] = YAML::Any.new(args[i + 1])
          i += 2
        end
      when "--override-analyze-prompt"
        if i + 1 < args.size && !args[i + 1].starts_with?("-")
          options["override_analyze_prompt"] = YAML::Any.new(args[i + 1])
          i += 2
        end
      when "--override-bundle-analyze-prompt"
        if i + 1 < args.size && !args[i + 1].starts_with?("-")
          options["override_bundle_analyze_prompt"] = YAML::Any.new(args[i + 1])
          i += 2
        end
      when "--override-llm-optimize-prompt"
        if i + 1 < args.size && !args[i + 1].starts_with?("-")
          options["override_llm_optimize_prompt"] = YAML::Any.new(args[i + 1])
          i += 2
        end
      else
        filtered_args << arg
        i += 1
      end
    end

    options["override_filter_prompt"].to_s.should eq("Custom filter")
    options["override_analyze_prompt"].to_s.should eq("Custom analyze")
    options["override_bundle_analyze_prompt"].to_s.should eq("Custom bundle")
    options["override_llm_optimize_prompt"].to_s.should eq("Custom optimize")
    filtered_args.should eq(["-b", "/tmp/test"])
  end
end